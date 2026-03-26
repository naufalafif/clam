import Foundation

// MARK: - Rate limit data from ~/.claude/usage-cache.json

struct UsageData: Equatable {
    let fiveHour: RateLimit
    let sevenDay: RateLimit
    let sevenDaySonnet: RateLimit?
    let dailyTokens: TokenUsage?
    let monthlyTokens: TokenUsage?

    static let empty = UsageData(
        fiveHour: .empty,
        sevenDay: .empty,
        sevenDaySonnet: nil,
        dailyTokens: nil,
        monthlyTokens: nil
    )
}

struct RateLimit: Equatable {
    let utilization: Double   // 0.0 – 1.0
    let resetsAt: Date?

    static let empty = RateLimit(utilization: 0, resetsAt: nil)

    var percentage: Int { Int((utilization * 100).rounded()) }

    var resetLabel: String {
        guard let date = resetsAt else { return "?" }
        let diff = date.timeIntervalSinceNow
        if diff < 86400 {
            let formatter = DateFormatter()
            formatter.dateFormat = "h a"
            return "@\(formatter.string(from: date).lowercased())"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return "@\(formatter.string(from: date).lowercased())"
        }
    }

    var color: LimitColor {
        if utilization >= 0.7 { return .red }
        if utilization >= 0.4 { return .yellow }
        return .green
    }
}

enum LimitColor {
    case green, yellow, red
}

struct TokenUsage: Equatable {
    let tokens: Int
    let cost: Double

    var formattedTokens: String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }

    var formattedCost: String {
        String(format: "$%.2f", cost)
    }
}
