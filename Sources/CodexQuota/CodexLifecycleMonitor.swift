import AppKit
import CodexQuotaCore
import Foundation

@MainActor
final class CodexLifecycleMonitor: NSObject {
    private let workspace = NSWorkspace.shared
    private var onChange: ((Bool) -> Void)?
    private var lastKnownState: Bool?

    func start(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        let center = workspace.notificationCenter
        center.addObserver(
            self,
            selector: #selector(applicationChanged),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationChanged),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        evaluate()
    }

    func stop() {
        workspace.notificationCenter.removeObserver(self)
        onChange = nil
    }

    @objc private func applicationChanged(_ notification: Notification) {
        evaluate()
    }

    private func evaluate() {
        let identifiers = workspace.runningApplications.map(\.bundleIdentifier)
        let isRunning = CodexLifecycleRule.isCodexRunning(bundleIdentifiers: identifiers)
        guard isRunning != lastKnownState else { return }
        lastKnownState = isRunning
        onChange?(isRunning)
    }
}
