import SwiftUI

// MARK: - A single active session row in the menu

struct SessionRowView: View {
    let session: ActiveSession
    let onFocus: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onFocus) {
            HStack(spacing: 8) {
                // Status dot
                Circle()
                    .fill(Color(hex: "#22c55e"))
                    .frame(width: 6, height: 6)

                // Session info
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Text(session.shortPath)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Terminal badge
                if let terminal = session.terminal {
                    Text(terminal.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        .onHover { isHovered = $0 }
    }
}
