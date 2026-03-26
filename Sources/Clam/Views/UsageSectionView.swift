import SwiftUI

// MARK: - Rate limits + token usage display

struct UsageSectionView: View {
    let usage: UsageData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            rateLimitRow("5hr", limit: usage.fiveHour)
            rateLimitRow("Weekly", limit: usage.sevenDay)
            if let sonnet = usage.sevenDaySonnet {
                rateLimitRow("Sonnet", limit: sonnet)
            }

            if usage.dailyTokens != nil || usage.monthlyTokens != nil {
                Divider().padding(.vertical, 2)
                if let daily = usage.dailyTokens   { tokenRow("Today", usage: daily) }
                if let monthly = usage.monthlyTokens { tokenRow("Month", usage: monthly) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func rateLimitRow(_ label: String, limit: RateLimit) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: limit))
                        .frame(width: geo.size.width * CGFloat(min(limit.utilization, 1.0)))
                        // Animate bar width whenever utilization changes
                        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: limit.utilization)
                }
                .frame(height: 4)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 4)

            Text("\(limit.percentage)%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(barColor(for: limit))
                .frame(width: 32, alignment: .trailing)
                .contentTransition(.numericText())

            Text(limit.resetLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 18)
    }

    @ViewBuilder
    private func tokenRow(_ label: String, usage: TokenUsage) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            Text(usage.formattedTokens)
                .font(.system(size: 11, design: .monospaced))
                .contentTransition(.numericText())
            Spacer()
            Text(usage.formattedCost)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func barColor(for limit: RateLimit) -> Color {
        switch limit.color {
        case .green:  return Color(hex: "#22c55e")
        case .yellow: return Color(hex: "#eab308")
        case .red:    return Color(hex: "#ef4444")
        }
    }
}
