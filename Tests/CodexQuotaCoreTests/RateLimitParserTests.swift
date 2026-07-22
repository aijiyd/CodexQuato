import Foundation
import Testing
@testable import CodexQuotaCore

@Suite("周额度解析")
struct RateLimitParserTests {
    @Test("从 codex 多额度响应解析周额度")
    func parsesWeeklyQuotaFromMultiBucketResponse() throws {
        let quota = try RateLimitParser.parseWeeklyQuota(from: response(
            primary: window(used: 15, minutes: 300, reset: 1_800_000_000),
            secondary: window(used: 58, minutes: 10_080, reset: 1_900_000_000),
            useMultiBucket: true
        ))

        #expect(quota.remainingPercent == 42)
        #expect(quota.resetsAt == Date(timeIntervalSince1970: 1_900_000_000))
    }

    @Test("兼容旧版单额度响应")
    func parsesBackwardCompatibleSnapshot() throws {
        let quota = try RateLimitParser.parseWeeklyQuota(from: response(
            primary: window(used: 4, minutes: 10_080, reset: 1_900_000_000),
            secondary: nil,
            useMultiBucket: false
        ))

        #expect(quota.remainingPercent == 96)
        #expect(quota.resetCredits == nil)
    }

    @Test("解析并按过期时间排列可用重置卡")
    func parsesResetCredits() throws {
        let quota = try RateLimitParser.parseWeeklyQuota(from: response(
            primary: window(used: 4, minutes: 10_080, reset: 1_900_000_000),
            secondary: nil,
            useMultiBucket: true,
            resetCredits: [
                "availableCount": 2,
                "credits": [
                    resetCredit(id: "later", expiresAt: 1_950_000_000),
                    resetCredit(id: "earlier", expiresAt: 1_940_000_000),
                    resetCredit(id: "used", status: "consumed", expiresAt: 1_930_000_000),
                ],
            ]
        ))

        #expect(quota.resetCredits?.map(\.id) == ["earlier", "later"])
        #expect(quota.resetCredits?.map(\.expiresAt) == [
            Date(timeIntervalSince1970: 1_940_000_000),
            Date(timeIntervalSince1970: 1_950_000_000),
        ])
    }

    @Test("支持没有可用重置卡")
    func parsesNoResetCredits() throws {
        let quota = try RateLimitParser.parseWeeklyQuota(from: response(
            primary: window(used: 4, minutes: 10_080, reset: 1_900_000_000),
            secondary: nil,
            useMultiBucket: true,
            resetCredits: ["availableCount": 0, "credits": []]
        ))

        #expect(quota.resetCredits == [])
    }

    @Test("重置卡数量不一致时失败")
    func rejectsResetCreditCountMismatch() {
        #expect(throws: RateLimitParsingError.resetCreditCountMismatch(expected: 2, actual: 1)) {
            try RateLimitParser.parseWeeklyQuota(from: response(
                primary: window(used: 4, minutes: 10_080, reset: 1_900_000_000),
                secondary: nil,
                useMultiBucket: true,
                resetCredits: [
                    "availableCount": 2,
                    "credits": [resetCredit(id: "only", expiresAt: 1_950_000_000)],
                ]
            ))
        }
    }

    @Test("缺失周额度时失败")
    func rejectsMissingWeeklyWindow() {
        #expect(throws: RateLimitParsingError.weeklyWindowMissing) {
            try RateLimitParser.parseWeeklyQuota(from: response(
                primary: window(used: 10, minutes: 300, reset: 1_900_000_000),
                secondary: nil,
                useMultiBucket: true
            ))
        }
    }

    @Test("重复周额度时失败")
    func rejectsDuplicatedWeeklyWindow() {
        #expect(throws: RateLimitParsingError.weeklyWindowDuplicated) {
            try RateLimitParser.parseWeeklyQuota(from: response(
                primary: window(used: 10, minutes: 10_080, reset: 1_900_000_000),
                secondary: window(used: 20, minutes: 10_080, reset: 1_900_000_001),
                useMultiBucket: true
            ))
        }
    }

    @Test("非法百分比时失败", arguments: [-1, 101])
    func rejectsInvalidPercent(_ usedPercent: Int) {
        #expect(throws: RateLimitParsingError.invalidUsedPercent(usedPercent)) {
            try RateLimitParser.parseWeeklyQuota(from: response(
                primary: window(used: usedPercent, minutes: 10_080, reset: 1_900_000_000),
                secondary: nil,
                useMultiBucket: true
            ))
        }
    }

    @Test("缺失重置时间时失败")
    func rejectsMissingResetTime() {
        #expect(throws: RateLimitParsingError.resetTimeMissing) {
            try RateLimitParser.parseWeeklyQuota(from: response(
                primary: window(used: 10, minutes: 10_080, reset: nil),
                secondary: nil,
                useMultiBucket: true
            ))
        }
    }

    @Test("服务器错误原样暴露")
    func exposesServerError() {
        let data = Data(#"{"id":2,"error":{"message":"not logged in"}}"#.utf8)
        #expect(throws: RateLimitParsingError.serverError("not logged in")) {
            try RateLimitParser.parseWeeklyQuota(from: data)
        }
    }

    private func response(
        primary: [String: Any]?,
        secondary: [String: Any]?,
        useMultiBucket: Bool,
        resetCredits: [String: Any]? = nil
    ) -> Data {
        let snapshot: [String: Any] = [
            "primary": primary ?? NSNull(),
            "secondary": secondary ?? NSNull(),
        ]
        var result: [String: Any] = ["rateLimits": snapshot]
        result["rateLimitsByLimitId"] = useMultiBucket ? ["codex": snapshot] : NSNull()
        if let resetCredits {
            result["rateLimitResetCredits"] = resetCredits
        }
        return try! JSONSerialization.data(withJSONObject: ["id": 2, "result": result])
    }

    private func window(used: Int, minutes: Int, reset: Int?) -> [String: Any] {
        [
            "usedPercent": used,
            "windowDurationMins": minutes,
            "resetsAt": reset ?? NSNull(),
        ]
    }

    private func resetCredit(
        id: String,
        status: String = "available",
        expiresAt: Int
    ) -> [String: Any] {
        [
            "id": id,
            "resetType": "codexRateLimits",
            "status": status,
            "expiresAt": expiresAt,
        ]
    }
}
