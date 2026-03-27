import Testing
import Foundation
@testable import ClamLib

@Suite("UsageMonitor parsing")
struct UsageMonitorParsingTests {

    @Test("parseRateLimitJSON extracts utilization and resets_at")
    func parseRateLimit() {
        let json: [String: Any] = [
            "five_hour": [
                "utilization": 45.0,
                "resets_at": "2026-03-27T03:00:00.845537+00:00"
            ] as [String: Any],
            "seven_day": [
                "utilization": 12.3
            ] as [String: Any]
        ]
        let result = UsageMonitor.parseRateLimitJSON(json)
        #expect(result.fiveHour.percentage == 45)
        #expect(result.fiveHour.resetsAt != nil)
        #expect(result.sevenDay.percentage == 12)
        #expect(result.sevenDaySonnet == nil)
    }

    @Test("parseRateLimitJSON handles seven_day_sonnet")
    func parseWithSonnet() {
        let json: [String: Any] = [
            "five_hour": ["utilization": 10.0] as [String: Any],
            "seven_day": ["utilization": 20.0] as [String: Any],
            "seven_day_sonnet": ["utilization": 30.0] as [String: Any]
        ]
        let result = UsageMonitor.parseRateLimitJSON(json)
        #expect(result.fiveHour.percentage == 10)
        #expect(result.sevenDay.percentage == 20)
        #expect(result.sevenDaySonnet?.percentage == 30)
    }

    @Test("parseRateLimitJSON returns empty for missing keys")
    func parseRateLimitEmpty() {
        let result = UsageMonitor.parseRateLimitJSON([:])
        #expect(result.fiveHour.percentage == 0)
        #expect(result.sevenDay.percentage == 0)
        #expect(result.sevenDaySonnet == nil)
    }

    @Test("parseTokenJSON extracts totals")
    func parseTokens() {
        let json: [String: Any] = [
            "totals": ["totalTokens": 150_000, "totalCost": 3.45] as [String: Any]
        ]
        let result = UsageMonitor.parseTokenJSON(json)
        #expect(result?.tokens == 150_000)
        #expect(result?.cost == 3.45)
    }

    @Test("parseTokenJSON returns nil for missing totals")
    func parseTokensNil() {
        #expect(UsageMonitor.parseTokenJSON([:]) == nil)
        #expect(UsageMonitor.parseTokenJSON(["totals": ["bad": true]]) == nil)
    }
}
