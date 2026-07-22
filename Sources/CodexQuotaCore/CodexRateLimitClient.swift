import Foundation

public enum CodexRateLimitClientError: LocalizedError, Equatable {
    case alreadyRunning
    case notRunning
    case launchFailed(String)
    case requestTimedOut
    case processExited(Int32)
    case invalidResponse
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "额度读取进程已经运行"
        case .notRunning:
            return "额度读取进程未运行"
        case let .launchFailed(message):
            return "无法启动 Codex 额度读取进程：\(message)"
        case .requestTimedOut:
            return "读取 Codex 额度超时"
        case let .processExited(status):
            return "Codex 额度读取进程已退出（\(status)）"
        case .invalidResponse:
            return "Codex 返回了无效响应"
        case let .writeFailed(message):
            return "无法向 Codex 发送请求：\(message)"
        }
    }
}

public final class CodexRateLimitClient: @unchecked Sendable {
    public typealias StartCompletion = @Sendable (Result<Void, Error>) -> Void
    public typealias ReadCompletion = @Sendable (Result<WeeklyQuota, Error>) -> Void

    private struct PendingRequest {
        let timeoutWorkItem: DispatchWorkItem
        let completion: @Sendable (Result<Data, Error>) -> Void
    }

    private let queue = DispatchQueue(label: "com.dengjiayi.codexquota.rpc")
    private let timeout: TimeInterval
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var outputBuffer = Data()
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var nextRequestID = 1
    private var stopping = false

    public init(timeout: TimeInterval = 8) {
        self.timeout = timeout
    }

    public func start(binaryURL: URL, completion: @escaping StartCompletion) {
        queue.async { [self] in
            guard process == nil else {
                completion(.failure(CodexRateLimitClientError.alreadyRunning))
                return
            }

            let child = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            child.executableURL = binaryURL
            child.arguments = ["app-server", "--stdio"]
            child.standardInput = inputPipe
            child.standardOutput = outputPipe
            child.standardError = FileHandle.nullDevice

            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let data = handle.availableData
                self.queue.async { [self] in
                    receiveOutput(data)
                }
            }
            child.terminationHandler = { [weak self] terminated in
                guard let self else { return }
                let status = terminated.terminationStatus
                self.queue.async { [self] in
                    handleProcessExit(status: status)
                }
            }

            do {
                try child.run()
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                completion(.failure(CodexRateLimitClientError.launchFailed(error.localizedDescription)))
                return
            }

            process = child
            inputHandle = inputPipe.fileHandleForWriting
            outputHandle = outputPipe.fileHandleForReading
            outputBuffer.removeAll(keepingCapacity: true)
            stopping = false

            sendRequest(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "CodexQuota",
                        "version": "1.0.0",
                    ],
                    "capabilities": NSNull(),
                ]
            ) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    do {
                        try self.writeNotification(method: "initialized")
                        completion(.success(()))
                    } catch {
                        self.stopLocked(reason: error)
                        completion(.failure(error))
                    }
                case let .failure(error):
                    completion(.failure(error))
                }
            }
        }
    }

    public func readWeeklyQuota(completion: @escaping ReadCompletion) {
        queue.async { [self] in
            guard process?.isRunning == true else {
                completion(.failure(CodexRateLimitClientError.notRunning))
                return
            }

            sendRequest(method: "account/rateLimits/read", params: nil) { result in
                switch result {
                case let .success(data):
                    do {
                        completion(.success(try RateLimitParser.parseWeeklyQuota(from: data)))
                    } catch {
                        completion(.failure(error))
                    }
                case let .failure(error):
                    completion(.failure(error))
                }
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            stopLocked(reason: CodexRateLimitClientError.notRunning)
        }
    }

    private func sendRequest(
        method: String,
        params: [String: Any]?,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        guard process?.isRunning == true else {
            completion(.failure(CodexRateLimitClientError.notRunning))
            return
        }

        let requestID = nextRequestID
        nextRequestID += 1

        var object: [String: Any] = [
            "id": requestID,
            "method": method,
        ]
        if let params {
            object["params"] = params
        }

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard let pending = self.pendingRequests.removeValue(forKey: requestID) else { return }
                pending.completion(.failure(CodexRateLimitClientError.requestTimedOut))
                self.stopLocked(reason: CodexRateLimitClientError.requestTimedOut)
            }
        }
        pendingRequests[requestID] = PendingRequest(
            timeoutWorkItem: timeoutWorkItem,
            completion: completion
        )

        do {
            try writeJSONObject(object)
            queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
        } catch {
            pendingRequests.removeValue(forKey: requestID)
            timeoutWorkItem.cancel()
            completion(.failure(error))
            stopLocked(reason: error)
        }
    }

    private func writeNotification(method: String) throws {
        try writeJSONObject(["method": method])
    }

    private func writeJSONObject(_ object: [String: Any]) throws {
        guard let inputHandle else {
            throw CodexRateLimitClientError.notRunning
        }
        do {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(0x0A)
            try inputHandle.write(contentsOf: data)
        } catch {
            throw CodexRateLimitClientError.writeFailed(error.localizedDescription)
        }
    }

    private func receiveOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        outputBuffer.append(data)

        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handleResponseLine(Data(line))
        }
    }

    private func handleResponseLine(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let requestID = object["id"] as? Int,
            let pending = pendingRequests.removeValue(forKey: requestID)
        else {
            return
        }

        pending.timeoutWorkItem.cancel()
        pending.completion(.success(data))
    }

    private func handleProcessExit(status: Int32) {
        guard process != nil else { return }
        let reason: Error = stopping
            ? CodexRateLimitClientError.notRunning
            : CodexRateLimitClientError.processExited(status)
        clearProcess(reason: reason)
    }

    private func stopLocked(reason: Error) {
        stopping = true
        outputHandle?.readabilityHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        clearProcess(reason: reason)
    }

    private func clearProcess(reason: Error) {
        outputHandle?.readabilityHandler = nil
        try? inputHandle?.close()
        try? outputHandle?.close()
        inputHandle = nil
        outputHandle = nil
        process = nil
        outputBuffer.removeAll(keepingCapacity: false)

        let pending = pendingRequests.values
        pendingRequests.removeAll()
        for request in pending {
            request.timeoutWorkItem.cancel()
            request.completion(.failure(reason))
        }
    }
}
