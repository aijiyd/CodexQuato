import AppKit
import CodexQuotaCore
import Foundation

@main
enum CodexQuotaMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppController()
        self.controller = controller
        controller.start()
        LoginItemRegistrar.registerIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}
