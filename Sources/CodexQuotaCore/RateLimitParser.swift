import Foundation

public enum RateLimitParsingError: LocalizedError, Equatable {
    case malformedResponse
    case serverError(String)
    case codexLimitMissing
    case windowMissing(QuotaWindowKind)
    case windowDuplicated(QuotaWindowKind)
    case invalidUsedPercent(QuotaWindowKind, Int)
    case resetTimeMissing(QuotaWindowKind)
    case invalidResetCreditCount(Int)
    case resetCreditCountMismatch(expected: Int, actual: Int)
    case invalidResetCreditExpiration(String)

    public var errorDescription: String? {
        switch self {
        case .malformedResponse:
            return "额度响应格式无效"
        case let .serverError(message):
            return "Codex 返回错误：\(message)"
        case .codexLimitMissing:
            return "Codex 未返回 codex 额度"
        case let .windowMissing(kind):
            return "Codex 未返回\(kind.displayName)"
        case let .windowDuplicated(kind):
            return "Codex 返回了重复的\(kind.displayName)"
        case let .invalidUsedPercent(kind, value):
            return "\(kind.displayName)百分比无效：\(value)"
        case let .resetTimeMissing(kind):
            return "Codex 未返回\(kind.displayName)重置时间"
        case let .invalidResetCreditCount(value):
            return "重置卡数量无效：\(value)"
        case let .resetCreditCountMismatch(expected, actual):
            return "重置卡数量不一致：声明 \(expected) 张，实际 \(actual) 张"
        case let .invalidResetCreditExpiration(id):
            return "重置卡过期时间无效：\(id)"
        }
    }
}

public enum QuotaWindowKind: Equatable, Sendable {
    case fiveHour
    case weekly

    fileprivate var displayName: String {
        switch self {
        case .fiveHour:
            return "5小时额度"
        case .weekly:
            return "周额度"
        }
    }
}

public enum RateLimitParser {
    private static let fiveHourWindowMinutes = 300
    private static let weeklyWindowMinutes = 10_080

    public static func parseQuotaSnapshot(from responseData: Data) throws -> QuotaSnapshot {
        let decoder = JSONDecoder()
        let envelope: RPCEnvelope
        do {
            envelope = try decoder.decode(RPCEnvelope.self, from: responseData)
        } catch {
            throw RateLimitParsingError.malformedResponse
        }

        if let error = envelope.error {
            throw RateLimitParsingError.serverError(error.message)
        }
        guard let result = envelope.result else {
            throw RateLimitParsingError.malformedResponse
        }

        let snapshot: RateLimitSnapshot
        if let byLimitID = result.rateLimitsByLimitId {
            guard let codex = byLimitID["codex"] else {
                throw RateLimitParsingError.codexLimitMissing
            }
            snapshot = codex
        } else {
            snapshot = result.rateLimits
        }

        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }
        let fiveHour = try parseWindow(
            from: windows,
            kind: .fiveHour,
            durationMinutes: fiveHourWindowMinutes,
            required: false
        )
        guard let weekly = try parseWindow(
            from: windows,
            kind: .weekly,
            durationMinutes: weeklyWindowMinutes,
            required: true
        ) else {
            throw RateLimitParsingError.windowMissing(.weekly)
        }

        let resetCredits = try result.rateLimitResetCredits.map(parseResetCredits)

        return QuotaSnapshot(
            fiveHour: fiveHour,
            weekly: weekly,
            resetCredits: resetCredits
        )
    }

    private static func parseWindow(
        from windows: [RateLimitWindow],
        kind: QuotaWindowKind,
        durationMinutes: Int,
        required: Bool
    ) throws -> QuotaWindow? {
        let matches = windows.filter { $0.windowDurationMins == durationMinutes }
        if matches.isEmpty {
            if required {
                throw RateLimitParsingError.windowMissing(kind)
            }
            return nil
        }
        guard matches.count == 1 else {
            throw RateLimitParsingError.windowDuplicated(kind)
        }

        let window = matches[0]
        guard (0...100).contains(window.usedPercent) else {
            throw RateLimitParsingError.invalidUsedPercent(kind, window.usedPercent)
        }
        guard let resetsAt = window.resetsAt, resetsAt > 0 else {
            throw RateLimitParsingError.resetTimeMissing(kind)
        }
        return QuotaWindow(
            remainingPercent: 100 - window.usedPercent,
            resetsAt: Date(timeIntervalSince1970: TimeInterval(resetsAt))
        )
    }

    private static func parseResetCredits(
        _ payload: RateLimitResetCreditsPayload
    ) throws -> [RateLimitResetCredit] {
        guard payload.availableCount >= 0 else {
            throw RateLimitParsingError.invalidResetCreditCount(payload.availableCount)
        }

        let availableCredits = payload.credits.filter {
            $0.status == "available" && $0.resetType == "codexRateLimits"
        }
        guard availableCredits.count == payload.availableCount else {
            throw RateLimitParsingError.resetCreditCountMismatch(
                expected: payload.availableCount,
                actual: availableCredits.count
            )
        }

        return try availableCredits.map { credit in
            guard credit.expiresAt > 0 else {
                throw RateLimitParsingError.invalidResetCreditExpiration(credit.id)
            }
            return RateLimitResetCredit(
                id: credit.id,
                expiresAt: Date(timeIntervalSince1970: TimeInterval(credit.expiresAt))
            )
        }
        .sorted { $0.expiresAt < $1.expiresAt }
    }
}

private struct RPCEnvelope: Decodable {
    let result: GetAccountRateLimitsResponse?
    let error: RPCError?
}

private struct RPCError: Decodable {
    let message: String
}

private struct GetAccountRateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: RateLimitResetCreditsPayload?
}

private struct RateLimitResetCreditsPayload: Decodable {
    let availableCount: Int
    let credits: [RateLimitResetCreditPayload]
}

private struct RateLimitResetCreditPayload: Decodable {
    let id: String
    let resetType: String
    let status: String
    let expiresAt: Int
}

private struct RateLimitSnapshot: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int?
}
