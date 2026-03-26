import SwiftUI

// MARK: - Menu bar status view (SF Symbol — built-in, always works)

struct MenuBarView: View {
    let activeCount: Int
    let fiveHourPct: Int
    let fiveHourReset: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "fossil.shell.fill")
                .font(.system(size: 13))

            Text("\(fiveHourPct)% \(fiveHourReset)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(height: 22)
        .fixedSize()
    }
}
