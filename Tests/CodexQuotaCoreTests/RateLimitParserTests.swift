import Foundation
import Testing
@testable import CodexQuotaCore

@Suite("额度快照解析")
struct RateLimitParserTests {
    @Test("从 codex 多额度响应解析5小时和周额度")
    func parsesQuotaSnapshotFromMultiBucketResponse() throws {
        let snapshot = try RateLimitParser.parseQuotaSnapshot(from: response(
            primary: window(used: 15, minutes: 300, reset: 1_800_000_000),
            secondary: window(used: 58, minutes: 10_080, reset: 1_900_000_000),
            useMultiBucket: true
        ))

        #expect(snapshot.fiveHour?.remainingPercent == 85)
        #expect(snapshot.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(snapshot.weekly.remainingPercent == 42)
        #expect(snapshot.weekly.resetsAt == Date(timeIntervalSince1970: 1_900_000_000))
    }

    @Test("额度顺序变化不影响识别")
    func parsesReversedQuotaWindows() throws {
        let snapshot = try RateLimitParser.parseQuotaSnapshot(from: response(
            primary: window(used: 58, minutes: 10_080, reset: 1_900_000_000),
            secondary: window(used: 15, minutes: 300, reset: 1_800_000_000),
            useMultiBucket: true
        ))

        #expect(snapshot.fiveHour?.remainingPercent == 85)
        #expect(snapshot.weekly.remainingPercent == 42)
    }

    @Test("5小时额度缺失时继续解析周额度")
    func parsesBackwardCompatibleSnapshot() throws {
        let snapshot = try RateLimitParser.parseQuotaSnapshot(from: response(
            primary: window(used: 4, minutes: 10_080, reset: 1_900_000_000),
            secondary: nil,
            useMultiBucket: false
        ))

        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.weekly.remainingPercent == 96)
        #expect(snapshot.resetCredits == nil)
    }

    @Test("解析并按过期时间排列可用重置卡")
    func parsesResetCredits() throws {
        let snapshot = try RateLimitParser.parseQuotaSnapshot(from: response(
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

        #expect(snapshot.resetCredits?.map(\.id) == ["earlier", "later"])
        #expect(snapshot.resetCredits?.map(\.expiresAt) == [
            Date(timeIntervalSince1970: 1_940_000_000),
            Date(timeIntervalSince1970: 1_950_000_000),
        ])
    }

    @Test("支持没有可用重置卡")
    func parsesNoResetCredits() throws {
        let snapshot = try RateLimitParser.parseQuotaSnapshot(from: response(
            primary: window(used: 4, minutes: 10_080, reset: 1_900_000_000),
            secondary: nil,
            useMultiBucket: true,
            resetCredits: ["availableCount": 0, "credits": []]
        ))

        #expect(snapshot.resetCredits == [])
    }

    @Test("重置卡数量不一致时失败")
    func rejectsResetCreditCountMismatch() {
        #expect(throws: RateLimitParsingError.resetCreditCountMismatch(expected: 2, actual: 1)) {
            try RateLimitParser.parseQuotaSnapshot(from: response(
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
        #expect(throws: RateLimitParsingError.windowMissing(.weekly)) {
            try RateLimitParser.parseQuotaSnapshot(from: response(
                primary: window(used: 10, minutes: 300, reset: 1_900_000_000),
                secondary: nil,
                useMultiBucket: true
            ))
        }
    }

    @Test("重复周额度时失败")
    func rejectsDuplicatedWeeklyWindow() {
        #expect(throws: RateLimitParsingError.windowDuplicated(.weekly)) {
            try RateLimitParser.parseQuotaSnapshot(from: response(
                primary: window(used: 10, minutes: 10_080, reset: 1_900_000_000),
                secondary: window(used: 20, minutes: 10_080, reset: 1_900_000_001),
                useMultiBucket: true
            ))
        }
    }

    @Test("周额度百分比非法时失败", arguments: [-1, 101])
    func rejectsInvalidWeeklyPercent(_ usedPercent: Int) {
        #expect(throws: RateLimitParsingError.invalidUsedPercent(.weekly, usedPercent)) {
            try RateLimitParser.parseQuotaSnapshot(from: response(
                primary: window(used: usedPercent, minutes: 10_080, reset: 1_900_000_000),
                secondary: nil,
                useMultiBucket: true
            ))
        }
    }

    @Test("周额度缺失重置时间时失败")
    func rejectsMissingWeeklyResetTime() {
        #expect(throws: RateLimitParsingError.resetTimeMissing(.weekly)) {
            try RateLimitParser.parseQuotaSnapshot(from: response(
                primary: window(used: 10, minutes: 10_080, reset: nil),
                secondary: nil,
                useMultiBucket: true
            ))
        }
    }

    @Test("重复5小时额度时失败")
    func rejectsDuplicatedFiveHourWindow() {
        #expect(throws: RateLimitParsingError.windowDuplicated(.fiveHour)) {
            try RateLimitParser.parseQuotaSnapshot(from: response(
                primary: window(used: 10, minutes: 300, reset: 1_900_000_000),
                secondary: window(used: 20, minutes: 300, reset: 1_900_000_001),
                useMultiBucket: true
            ))
        }
    }

    @Test("5小时额度百分比非法时失败", arguments: [-1, 101])
    func rejectsInvalidFiveHourPercent(_ usedPercent: Int) {
        #expect(throws: RateLimitParsingError.invalidUsedPercent(.fiveHour, usedPercent)) {
            try RateLimitParser.parseQuotaSnapshot(from: response(
                primary: window(used: usedPercent, minutes: 300, reset: 1_800_000_000),
                secondary: window(used: 10, minutes: 10_080, reset: 1_900_000_000),
                useMultiBucket: true
            ))
        }
    }

    @Test("5小时额度缺失重置时间时失败")
    func rejectsMissingFiveHourResetTime() {
        #expect(throws: RateLimitParsingError.resetTimeMissing(.fiveHour)) {
            try RateLimitParser.parseQuotaSnapshot(from: response(
                primary: window(used: 10, minutes: 300, reset: nil),
                secondary: window(used: 10, minutes: 10_080, reset: 1_900_000_000),
                useMultiBucket: true
            ))
        }
    }

    @Test("服务器错误原样暴露")
    func exposesServerError() {
        let data = Data(#"{"id":2,"error":{"message":"not logged in"}}"#.utf8)
        #expect(throws: RateLimitParsingError.serverError("not logged in")) {
            try RateLimitParser.parseQuotaSnapshot(from: data)
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
