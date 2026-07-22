import CodexQuotaCore
import Foundation

enum AppSettings {
    private static let refreshIntervalKey = "refreshIntervalSeconds"

    static var refreshInterval: RefreshIntervalOption {
        get {
            let storedValue = UserDefaults.standard.integer(forKey: refreshIntervalKey)
            return RefreshIntervalOption(rawValue: storedValue) ?? .oneMinute
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: refreshIntervalKey)
        }
    }
}
