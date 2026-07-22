import Foundation

public enum RateLimitParsingError: LocalizedError, Equatable {
    case malformedResponse
    case serverError(String)
    case codexLimitMissing
    case weeklyWindowMissing
    case weeklyWindowDuplicated
    case invalidUsedPercent(Int)
    case resetTimeMissing
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
        case .weeklyWindowMissing:
            return "Codex 未返回周额度"
        case .weeklyWindowDuplicated:
            return "Codex 返回了重复的周额度"
        case let .invalidUsedPercent(value):
            return "周额度百分比无效：\(value)"
        case .resetTimeMissing:
            return "Codex 未返回周额度重置时间"
        case let .invalidResetCreditCount(value):
            return "重置卡数量无效：\(value)"
        case let .resetCreditCountMismatch(expected, actual):
            return "重置卡数量不一致：声明 \(expected) 张，实际 \(actual) 张"
        case let .invalidResetCreditExpiration(id):
            return "重置卡过期时间无效：\(id)"
        }
    }
}

public enum RateLimitParser {
    private static let weeklyWindowMinutes = 10_080

    public static func parseWeeklyQuota(from responseData: Data) throws -> WeeklyQuota {
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

        let weeklyWindows = [snapshot.primary, snapshot.secondary]
            .compactMap { $0 }
            .filter { $0.windowDurationMins == weeklyWindowMinutes }

        guard !weeklyWindows.isEmpty else {
            throw RateLimitParsingError.weeklyWindowMissing
        }
        guard weeklyWindows.count == 1 else {
            throw RateLimitParsingError.weeklyWindowDuplicated
        }

        let weekly = weeklyWindows[0]
        guard (0...100).contains(weekly.usedPercent) else {
            throw RateLimitParsingError.invalidUsedPercent(weekly.usedPercent)
        }
        guard let resetsAt = weekly.resetsAt, resetsAt > 0 else {
            throw RateLimitParsingError.resetTimeMissing
        }

        let resetCredits = try result.rateLimitResetCredits.map(parseResetCredits)

        return WeeklyQuota(
            remainingPercent: 100 - weekly.usedPercent,
            resetsAt: Date(timeIntervalSince1970: TimeInterval(resetsAt)),
            resetCredits: resetCredits
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
