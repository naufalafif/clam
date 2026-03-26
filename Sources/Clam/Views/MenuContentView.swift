import SwiftUI

// MARK: - Main popover content

struct MenuContentView: View {
    @ObservedObject var state: SessionState
    let onFocusSession: (ActiveSession) -> Void
    let onOpenSearch: () -> Void
    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            // Sessions scrollable — variable height
            ScrollView {
                sessionsSection
            }

            Divider().padding(.vertical, 2)
            // Usage pinned — fixed height
            usageSection
            Divider().padding(.vertical, 2)
            // Actions pinned at bottom — always visible
            actionsSection
                .padding(.bottom, 6)
        }
        .frame(width: 300, height: 420)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "fossil.shell.fill")
                .font(.system(size: 12))
            Text("Clam")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            if state.isRefreshing {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 14, height: 14)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                state.isSessionsLoaded
                    ? (state.activeSessions.isEmpty ? "Sessions" : "Sessions (\(state.activeSessions.count))")
                    : "Sessions"
            )

            if !state.isSessionsLoaded {
                // Skeleton
                ForEach(0..<2, id: \.self) { _ in SessionSkeletonRow() }
            } else if state.activeSessions.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 6, height: 6)
                    Text("No active sessions")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                ForEach(state.activeSessions) { session in
                    SessionRowView(session: session) { onFocusSession(session) }
                }
            }
        }
    }

    // MARK: - Usage

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Usage")
            if state.isUsageLoaded {
                UsageSectionView(usage: state.usageData)
            } else {
                UsageSkeletonView()
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 0) {
            Button(action: onRefresh) {
                HStack {
                    if state.isRefreshing {
                        ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12)).frame(width: 16)
                    }
                    Text(state.isRefreshing ? "Refreshing…" : "Refresh")
                        .font(.system(size: 12))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect()
            .disabled(state.isRefreshing)
            menuButton(label: "Search Sessions…", icon: "magnifyingglass", shortcut: "⌘K") { onOpenSearch() }
            menuButton(label: "Settings…", icon: "gearshape") { onSettings() }
            Divider().padding(.vertical, 2)
            menuButton(label: "Quit", icon: "power") { onQuit() }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func menuButton(label: String, icon: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 16)
                Text(label).font(.system(size: 12))
                Spacer()
                if let shortcut {
                    Text(shortcut).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }
}

// MARK: - Skeleton: session row

private struct SessionSkeletonRow: View {
    @State private var opacity: Double = 0.5

    var body: some View {
        HStack(spacing: 8) {
            SkeletonPill(width: 6, height: 6, corner: 3)
            VStack(alignment: .leading, spacing: 4) {
                SkeletonPill(width: 90, height: 9)
                SkeletonPill(width: 130, height: 7)
            }
            Spacer()
            SkeletonPill(width: 44, height: 14, corner: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                opacity = 0.25
            }
        }
    }
}

// MARK: - Skeleton: usage section

private struct UsageSkeletonView: View {
    @State private var opacity: Double = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 6) {
                    SkeletonPill(width: 40, height: 8)
                    SkeletonPill(width: .infinity, height: 4, corner: 2)
                    SkeletonPill(width: 28, height: 8)
                    SkeletonPill(width: 28, height: 8)
                }
                .frame(height: 18)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                opacity = 0.25
            }
        }
    }
}

// MARK: - Skeleton primitive

struct SkeletonPill: View {
    let width: CGFloat
    let height: CGFloat
    var corner: CGFloat = 3

    init(width: CGFloat, height: CGFloat, corner: CGFloat = 3) {
        self.width = width
        self.height = height
        self.corner = corner
    }

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(Color.primary.opacity(0.15))
            .frame(width: width == .infinity ? nil : width, height: height)
            .frame(maxWidth: width == .infinity ? .infinity : nil)
    }
}

// MARK: - Hover modifier

private struct HoverEffectModifier: ViewModifier {
    @State private var isHovered = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                    .padding(.horizontal, 5)
            )
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

extension View {
    func hoverEffect() -> some View { modifier(HoverEffectModifier()) }
}
