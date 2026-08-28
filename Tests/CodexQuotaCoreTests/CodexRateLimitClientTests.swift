import Foundation
import Testing
@testable import CodexQuotaCore

@Suite("Codex 协议客户端")
struct CodexRateLimitClientTests {
    @Test(
        "本机 Codex 只读额度冒烟测试",
        .enabled(if: ProcessInfo.processInfo.environment["CODEXQUOTA_LIVE_SMOKE"] == "1")
    )
    func liveCodexSmokeTest() async {
        let binaryURL = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            Issue.record("找不到本机 Codex 内置程序")
            return
        }

        let client = CodexRateLimitClient(timeout: 8)
        if let error = await start(client, binaryURL: binaryURL) {
            Issue.record("无法连接本机 Codex：\(error)")
            return
        }
        guard case let .success(snapshot) = await read(client) else {
            Issue.record("本机 Codex 未返回有效额度快照")
            return
        }
        #expect(snapshot.fiveHour != nil)
        if let fiveHour = snapshot.fiveHour {
            #expect((0...100).contains(fiveHour.remainingPercent))
            #expect(fiveHour.resetsAt > Date())
        }
        #expect((0...100).contains(snapshot.weekly.remainingPercent))
        #expect(snapshot.weekly.resetsAt > Date())
        client.stop()
    }

    @Test("完成初始化并读取额度快照")
    func readsQuotaSnapshot() async throws {
        let fakeCodex = try makeFakeCodex(mode: "success")
        defer { try? FileManager.default.removeItem(at: fakeCodex.deletingLastPathComponent()) }

        let client = CodexRateLimitClient(timeout: 1)
        #expect(await start(client, binaryURL: fakeCodex) == nil)

        let outcome = await read(client)
        guard case let .success(snapshot) = outcome else {
            Issue.record("预期成功读取周额度，实际为 \(outcome)")
            return
        }
        #expect(snapshot.fiveHour?.remainingPercent == 75)
        #expect(snapshot.weekly.remainingPercent == 42)
        client.stop()
    }

    @Test("请求超时后终止进程")
    func timesOut() async throws {
        let fakeCodex = try makeFakeCodex(mode: "timeout")
        defer { try? FileManager.default.removeItem(at: fakeCodex.deletingLastPathComponent()) }

        let client = CodexRateLimitClient(timeout: 1)
        #expect(await start(client, binaryURL: fakeCodex) == nil)

        let outcome = await read(client)
        guard case let .failure(message) = outcome else {
            Issue.record("预期请求超时")
            return
        }
        #expect(message.contains("超时"))
    }

    @Test("子进程退出后可以重新连接")
    func reconnectsAfterProcessExit() async throws {
        let exitingCodex = try makeFakeCodex(mode: "exit")
        let successfulCodex = try makeFakeCodex(mode: "success")
        defer {
            try? FileManager.default.removeItem(at: exitingCodex.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: successfulCodex.deletingLastPathComponent())
        }

        let client = CodexRateLimitClient(timeout: 1)
        #expect(await start(client, binaryURL: exitingCodex) == nil)
        guard case let .failure(message) = await read(client) else {
            Issue.record("预期子进程退出错误")
            return
        }
        #expect(message.contains("已退出"))

        #expect(await start(client, binaryURL: successfulCodex) == nil)
        guard case let .success(snapshot) = await read(client) else {
            Issue.record("预期重新连接后成功")
            return
        }
        #expect(snapshot.fiveHour?.remainingPercent == 75)
        #expect(snapshot.weekly.remainingPercent == 42)
        client.stop()
    }

    private enum ReadOutcome: CustomStringConvertible, Sendable {
        case success(QuotaSnapshot)
        case failure(String)

        var description: String {
            switch self {
            case let .success(snapshot):
                return "success(weekly: \(snapshot.weekly.remainingPercent))"
            case let .failure(message):
                return "failure(\(message))"
            }
        }
    }

    private func start(_ client: CodexRateLimitClient, binaryURL: URL) async -> String? {
        await withCheckedContinuation { continuation in
            client.start(binaryURL: binaryURL) { result in
                switch result {
                case .success:
                    continuation.resume(returning: nil)
                case let .failure(error):
                    continuation.resume(returning: error.localizedDescription)
                }
            }
        }
    }

    private func read(_ client: CodexRateLimitClient) async -> ReadOutcome {
        await withCheckedContinuation { continuation in
            client.readQuotaSnapshot { result in
                switch result {
                case let .success(quota):
                    continuation.resume(returning: .success(quota))
                case let .failure(error):
                    continuation.resume(returning: .failure(error.localizedDescription))
                }
            }
        }
    }

    private func makeFakeCodex(mode: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("codex")
        let script = #"""
        #!/bin/zsh
        mode="__MODE__"
        while IFS= read -r line; do
            if [[ "$line" != *'"id":'* ]]; then
                continue
            fi
            id="${line#*\"id\":}"
            id="${id%%,*}"
            id="${id%%\}*}"
            if [[ "$line" == *initialize* ]]; then
                printf '{"id":%s,"result":{"userAgent":"fake"}}\n' "$id"
            elif [[ "$line" == *rateLimits* ]]; then
                if [[ "$mode" == "timeout" ]]; then
                    continue
                fi
                if [[ "$mode" == "exit" ]]; then
                    exit 7
                fi
                printf '{"id":%s,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":58,"windowDurationMins":10080,"resetsAt":1900000000}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":58,"windowDurationMins":10080,"resetsAt":1900000000}}}}}\n' "$id"
            fi
        done
        """#.replacingOccurrences(of: "__MODE__", with: mode)
        try Data(script.utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }
}
