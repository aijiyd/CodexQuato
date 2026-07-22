import AppKit
import CodexQuotaCore
import Foundation

enum CodexBinaryLocator {
    static func locate() -> URL? {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: CodexLifecycleRule.bundleIdentifier
        ) else {
            return nil
        }

        let binaryURL = applicationURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            return nil
        }
        return binaryURL
    }
}
