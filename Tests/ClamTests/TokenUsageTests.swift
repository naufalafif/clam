import Testing
@testable import ClamLib

@Suite("TokenUsage")
struct TokenUsageTests {

    // MARK: - formattedTokens

    @Test("formattedTokens shows raw count below 1K")
    func belowThousand() {
        #expect(TokenUsage(tokens: 0, cost: 0).formattedTokens == "0")
        #expect(TokenUsage(tokens: 500, cost: 0).formattedTokens == "500")
        #expect(TokenUsage(tokens: 999, cost: 0).formattedTokens == "999")
    }

    @Test("formattedTokens shows K for thousands")
    func thousands() {
        #expect(TokenUsage(tokens: 1000, cost: 0).formattedTokens == "1.0K")
        #expect(TokenUsage(tokens: 1500, cost: 0).formattedTokens == "1.5K")
        #expect(TokenUsage(tokens: 50_000, cost: 0).formattedTokens == "50.0K")
    }

    @Test("formattedTokens shows M for millions")
    func millions() {
        #expect(TokenUsage(tokens: 1_000_000, cost: 0).formattedTokens == "1.0M")
        #expect(TokenUsage(tokens: 2_500_000, cost: 0).formattedTokens == "2.5M")
    }

    // MARK: - formattedCost

    @Test("formattedCost formats as dollars with 2 decimals")
    func cost() {
        #expect(TokenUsage(tokens: 0, cost: 0).formattedCost == "$0.00")
        #expect(TokenUsage(tokens: 0, cost: 1.5).formattedCost == "$1.50")
        #expect(TokenUsage(tokens: 0, cost: 123.456).formattedCost == "$123.46")
    }
}
