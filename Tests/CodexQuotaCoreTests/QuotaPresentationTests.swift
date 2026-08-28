import Testing
@testable import CodexQuotaCore

@Suite("状态栏显示规则")
struct QuotaPresentationTests {
    @Test("只有100%使用加宽画布")
    func indicatorWidths() {
        #expect(QuotaPresentation.indicatorWidth(for: nil) == 56)
        #expect(QuotaPresentation.indicatorWidth(for: 99) == 56)
        #expect(QuotaPresentation.indicatorWidth(for: 100) == 62)
        #expect(QuotaPresentation.dualIndicatorWidth(fiveHourPercent: 99, weeklyPercent: 42) == 56)
        #expect(QuotaPresentation.dualIndicatorWidth(fiveHourPercent: 100, weeklyPercent: 42) == 62)
        #expect(QuotaPresentation.dualIndicatorWidth(fiveHourPercent: 42, weeklyPercent: 100) == 62)
    }

    @Test("颜色边界", arguments: [
        (19, QuotaColorBand.critical),
        (20, QuotaColorBand.warning),
        (60, QuotaColorBand.warning),
        (61, QuotaColorBand.healthy),
    ])
    func colorBoundaries(percent: Int, expected: QuotaColorBand) {
        #expect(QuotaPresentation.colorBand(for: percent) == expected)
    }

    @Test("五段短条数量", arguments: [
        (0, 0),
        (20, 1),
        (42, 2),
        (60, 3),
        (100, 5),
    ])
    func segmentCounts(percent: Int, expected: Int) {
        #expect(QuotaPresentation.filledSegmentCount(for: percent) == expected)
    }

    @Test("只识别 Codex 应用")
    func lifecycleRule() {
        #expect(CodexLifecycleRule.isCodexRunning(bundleIdentifiers: ["com.apple.finder", "com.openai.codex"]))
        #expect(!CodexLifecycleRule.isCodexRunning(bundleIdentifiers: ["com.apple.finder", nil]))
    }

    @Test("刷新频率选项固定且完整")
    func refreshIntervals() {
        #expect(RefreshIntervalOption.allCases.map(\.rawValue) == [1, 5, 10, 15, 30, 60, 120, 300, 900])
        #expect(RefreshIntervalOption.allCases.map(\.title) == ["1 秒", "5 秒", "10 秒", "15 秒", "30 秒", "1 分钟", "2 分钟", "5 分钟", "15 分钟"])
    }
}
