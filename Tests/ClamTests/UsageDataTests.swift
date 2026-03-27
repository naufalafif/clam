import Testing
@testable import ClamLib

@Suite("UsageData")
struct UsageDataTests {

    @Test("empty has zero utilization across all limits")
    func empty() {
        let data = UsageData.empty
        #expect(data.fiveHour.percentage == 0)
        #expect(data.sevenDay.percentage == 0)
        #expect(data.sevenDaySonnet == nil)
        #expect(data.dailyTokens == nil)
        #expect(data.monthlyTokens == nil)
    }

    @Test("equality works for identical values")
    func equality() {
        let a = UsageData(
            fiveHour: RateLimit(utilization: 0.5, resetsAt: nil),
            sevenDay: RateLimit(utilization: 0.3, resetsAt: nil),
            sevenDaySonnet: nil,
            dailyTokens: TokenUsage(tokens: 1000, cost: 1.0),
            monthlyTokens: nil
        )
        let b = UsageData(
            fiveHour: RateLimit(utilization: 0.5, resetsAt: nil),
            sevenDay: RateLimit(utilization: 0.3, resetsAt: nil),
            sevenDaySonnet: nil,
            dailyTokens: TokenUsage(tokens: 1000, cost: 1.0),
            monthlyTokens: nil
        )
        #expect(a == b)
    }
}
