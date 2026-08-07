import AppKit
import Foundation
import ServiceManagement

@MainActor
enum LoginItemRegistrar {
    private static let approvalAlertShownKey = "loginItemApprovalAlertShown"
    private static var registrationDisabled: Bool {
        ProcessInfo.processInfo.environment["CODEXQUOTA_DISABLE_LOGIN_ITEM_REGISTRATION"] == "1"
            || Bundle.main.bundleIdentifier?.hasSuffix(".preview") == true
    }

    static func registerIfNeeded() {
        if registrationDisabled {
            return
        }

        let service = SMAppService.mainApp
        if service.status == .notRegistered {
            do {
                try service.register()
            } catch {
                showApprovalAlertIfNeeded()
                return
            }
        }

        if service.status == .requiresApproval {
            showApprovalAlertIfNeeded()
        }
    }

    private static func showApprovalAlertIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: approvalAlertShownKey) else { return }
        defaults.set(true, forKey: approvalAlertShownKey)

        showApprovalAlert()
    }

    private static func showApprovalAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "需要允许登录时启动"
        alert.informativeText = "请在系统设置的“登录项”中允许 Codex 额度监控，才能在重启 Mac 后继续自动跟随 Codex。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
