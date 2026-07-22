import AppKit
import Foundation
import ServiceManagement

enum LoginItemState {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

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

    static func currentState() -> LoginItemState {
        if registrationDisabled {
            return .unavailable
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> LoginItemState {
        if registrationDisabled {
            return .unavailable
        }

        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .notRegistered {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            showErrorAlert(message: error.localizedDescription)
        }

        if service.status == .requiresApproval {
            showApprovalAlert()
        }
        return currentState()
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

    private static func showErrorAlert(message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法修改登录项"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
