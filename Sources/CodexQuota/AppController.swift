import AppKit
import CodexQuotaCore
import Foundation

@MainActor
final class AppController: NSObject {
    private let statusItemController = StatusItemController()
    private let lifecycleMonitor = CodexLifecycleMonitor()
    private var rateLimitClient: CodexRateLimitClient?
    private var refreshTimer: Timer?
    private var codexIsRunning = false
    private var requestInFlight = false
    private var refreshInterval = AppSettings.refreshInterval

    override init() {
        super.init()
        statusItemController.configureActions(
            onRefresh: { [weak self] in
                self?.refreshNow()
            },
            onIntervalChanged: { [weak self] option in
                self?.changeRefreshInterval(to: option)
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
    }

    func start() {
        lifecycleMonitor.start { [weak self] isRunning in
            self?.handleCodexRunningChanged(isRunning)
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        lifecycleMonitor.stop()
        rateLimitClient?.stop()
        rateLimitClient = nil
    }

    private func refreshNow() {
        guard codexIsRunning, !requestInFlight else { return }
        if rateLimitClient == nil {
            connectAndRefresh()
        } else {
            requestQuota()
        }
    }

    @objc private func refreshTimerFired() {
        refreshNow()
    }

    private func changeRefreshInterval(to option: RefreshIntervalOption) {
        guard option != refreshInterval else { return }
        refreshInterval = option
        AppSettings.refreshInterval = option
        if codexIsRunning {
            startRefreshTimer()
        }
    }

    private func handleCodexRunningChanged(_ isRunning: Bool) {
        guard isRunning != codexIsRunning else { return }
        codexIsRunning = isRunning

        if isRunning {
            statusItemController.show(
                state: .loading,
                refreshInterval: refreshInterval
            )
            startRefreshTimer()
            connectAndRefresh()
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            requestInFlight = false
            rateLimitClient?.stop()
            rateLimitClient = nil
            statusItemController.hide()
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: TimeInterval(refreshInterval.rawValue),
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func connectAndRefresh() {
        guard codexIsRunning, !requestInFlight else { return }
        guard let binaryURL = CodexBinaryLocator.locate() else {
            updateStatus(state: .unavailable("找不到 Codex 内置程序"))
            return
        }

        let client = CodexRateLimitClient(timeout: 8)
        rateLimitClient = client
        requestInFlight = true
        updateStatus(state: .loading)

        client.start(binaryURL: binaryURL) { [weak self, weak client] result in
            Task { @MainActor in
                guard let self, self.codexIsRunning, self.rateLimitClient === client else { return }
                switch result {
                case .success:
                    self.requestInFlight = false
                    self.requestQuota()
                case let .failure(error):
                    self.requestInFlight = false
                    self.rateLimitClient = nil
                    self.updateStatus(state: .unavailable(error.localizedDescription))
                }
            }
        }
    }

    private func requestQuota() {
        guard codexIsRunning, !requestInFlight else { return }
        guard let client = rateLimitClient else {
            connectAndRefresh()
            return
        }

        requestInFlight = true
        client.readQuotaSnapshot { [weak self, weak client] result in
            Task { @MainActor in
                guard let self, self.codexIsRunning, self.rateLimitClient === client else { return }
                self.requestInFlight = false
                switch result {
                case let .success(quota):
                    self.updateStatus(state: .available(quota))
                case let .failure(error):
                    client?.stop()
                    self.rateLimitClient = nil
                    self.updateStatus(state: .unavailable(error.localizedDescription))
                }
            }
        }
    }

    private func updateStatus(state: QuotaState) {
        statusItemController.update(
            state: state,
            refreshInterval: refreshInterval
        )
    }
}
