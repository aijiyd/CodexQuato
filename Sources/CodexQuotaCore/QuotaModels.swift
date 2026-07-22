import Foundation

public struct WeeklyQuota: Equatable, Sendable {
    public let remainingPercent: Int
    public let resetsAt: Date
    public let resetCredits: [RateLimitResetCredit]?

    public init(
        remainingPercent: Int,
        resetsAt: Date,
        resetCredits: [RateLimitResetCredit]? = nil
    ) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.resetCredits = resetCredits
    }
}

public struct RateLimitResetCredit: Equatable, Sendable {
    public let id: String
    public let expiresAt: Date

    public init(id: String, expiresAt: Date) {
        self.id = id
        self.expiresAt = expiresAt
    }
}

public enum QuotaState: Equatable, Sendable {
    case loading
    case available(WeeklyQuota)
    case unavailable(String)
}

public enum QuotaColorBand: Equatable, Sendable {
    case healthy
    case warning
    case critical
}

public enum QuotaPresentation {
    public static func colorBand(for remainingPercent: Int) -> QuotaColorBand {
        switch remainingPercent {
        case 61...100:
            return .healthy
        case 20...60:
            return .warning
        default:
            return .critical
        }
    }

    public static func filledSegmentCount(for remainingPercent: Int) -> Int {
        guard (0...100).contains(remainingPercent) else { return 0 }
        return Int((Double(remainingPercent) / 20.0).rounded())
    }
}

public enum RefreshIntervalOption: Int, CaseIterable, Equatable, Sendable {
    case oneSecond = 1
    case fiveSeconds = 5
    case tenSeconds = 10
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case fifteenMinutes = 900

    public var title: String {
        switch self {
        case .oneSecond:
            return "1 秒"
        case .fiveSeconds:
            return "5 秒"
        case .tenSeconds:
            return "10 秒"
        case .fifteenSeconds:
            return "15 秒"
        case .thirtySeconds:
            return "30 秒"
        case .oneMinute:
            return "1 分钟"
        case .twoMinutes:
            return "2 分钟"
        case .fiveMinutes:
            return "5 分钟"
        case .fifteenMinutes:
            return "15 分钟"
        }
    }
}

public enum CodexLifecycleRule {
    public static let bundleIdentifier = "com.openai.codex"

    public static func isCodexRunning(bundleIdentifiers: [String?]) -> Bool {
        bundleIdentifiers.contains { $0 == bundleIdentifier }
    }
}
