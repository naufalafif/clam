import AppKit
import SwiftUI

// MARK: - Observable model shared between controller and view

@MainActor
class SessionSearchModel: ObservableObject {
    @Published var sessions: [PastSession] = []
    @Published var isLoading = true       // true only when no data at all
    @Published var isRefreshing = false   // true when refreshing with existing data
}

// MARK: - Floating spotlight-style search window for past sessions

@MainActor
class SessionSearchPanelController {
    private var panel: NSPanel?
    private let launcher: TerminalLauncher
    private let monitor: SessionMonitor
    private var model = SessionSearchModel()

    /// Persistent cache — survives between opens so re-open is instant
    private var sessionCache: [PastSession] = []
    private var cacheDate: Date?
    private let cacheTTL: TimeInterval = 30
    private var onFocusSession: ((ActiveSession) -> Void)?
    private var currentActiveSessions: [ActiveSession] = []

    init(launcher: TerminalLauncher, monitor: SessionMonitor) {
        self.launcher = launcher
        self.monitor = monitor
    }

    /// Pre-warm cache in background on app launch
    func prewarm() async {
        guard sessionCache.isEmpty else { return }
        sessionCache = await monitor.fetchPastSessions()
        cacheDate = Date()
    }

    func show(
        preferredTerminal: TerminalLauncher.PreferredTerminal,
        activeSessions: [ActiveSession] = [],
        onFocusSession: ((ActiveSession) -> Void)? = nil
    ) {
        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let activeSessionIds = Set(activeSessions.map(\.sessionId))
        let activeAsPast = activeSessions.map { session in
            PastSession(
                sessionId: session.sessionId,
                cwd: session.cwd,
                projectDir: "",
                lastMessageAt: session.startedAt,
                firstUserMessage: "",
                isActive: true,
                terminal: session.terminal
            )
        }

        let hasCachedData = !sessionCache.isEmpty
        let cacheAge = cacheDate.map { Date().timeIntervalSince($0) } ?? .infinity
        let cacheStale = cacheAge > cacheTTL

        // Show panel immediately with whatever we have
        model = SessionSearchModel()
        let pastOnly = sessionCache.filter { !activeSessionIds.contains($0.sessionId) }
        model.sessions = activeAsPast + pastOnly
        model.isLoading = !hasCachedData && activeSessions.isEmpty
        model.isRefreshing = hasCachedData && cacheStale
        self.onFocusSession = onFocusSession
        self.currentActiveSessions = activeSessions
        presentPanel(preferredTerminal: preferredTerminal)

        // Only re-fetch if cache is empty or stale
        guard !hasCachedData || cacheStale else { return }

        Task {
            let all = await monitor.fetchPastSessions()
            sessionCache = all
            cacheDate = Date()
            let pastFiltered = all.filter { !activeSessionIds.contains($0.sessionId) }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                model.sessions = activeAsPast + pastFiltered
                model.isLoading = false
                model.isRefreshing = false
            }
        }
    }

    private func presentPanel(preferredTerminal: TerminalLauncher.PreferredTerminal) {
        let view = SessionSearchView(
            model: model,
            onSelect: { [weak self] session in
                guard let self else { return }
                if session.isActive,
                   let active = self.currentActiveSessions.first(where: { $0.sessionId == session.sessionId }) {
                    self.onFocusSession?(active)
                    self.panel?.close()
                } else {
                    Task {
                        await self.launcher.resume(
                            sessionId: session.sessionId,
                            cwd: session.cwd,
                            preferred: preferredTerminal
                        )
                        self.panel?.close()
                    }
                }
            },
            onClose: { [weak self] in self?.panel?.close() }
        )

        let hosting = NSHostingController(rootView: view)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.contentViewController = hosting
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient]

        if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: vis.midX - 280, y: vis.midY - 100))
        }

        panel = p
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SwiftUI search view

struct SessionSearchView: View {
    @ObservedObject var model: SessionSearchModel
    let onSelect: (PastSession) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedId: String?

    private var filtered: [PastSession] {
        guard !query.isEmpty else { return model.sessions }
        let q = query.lowercased()
        return model.sessions.filter {
            $0.displayName.lowercased().contains(q)
                || $0.shortPath.lowercased().contains(q)
                || $0.firstUserMessage.lowercased().contains(q)
                || $0.sessionId.lowercased().hasPrefix(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))

                TextField("Search sessions…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))

                if model.isLoading || model.isRefreshing {
                    ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                        .transition(.opacity)
                } else if !query.isEmpty {
                    Button(
                        action: { query = "" },
                        label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    )
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.isLoading)
            .animation(.easeInOut(duration: 0.2), value: model.isRefreshing)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)

            Divider()

            Group {
                if model.isLoading {
                    Spacer()
                    ProgressView("Loading sessions…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text(query.isEmpty ? "No past sessions found" : "No results for \"\(query)\"")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { session in
                                PastSessionRowView(
                                    session: session,
                                    isSelected: selectedId == session.id
                                ) { onSelect(session) }
                                .onHover { if $0 { selectedId = session.id } }
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                ))

                                if session.id != filtered.last?.id {
                                    Divider().padding(.horizontal, 16)
                                }
                            }
                        }
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: filtered.map(\.id))
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                if model.isLoading {
                    Text("Loading…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text("\(filtered.count) session\(filtered.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                        if model.isRefreshing {
                            Text("· refreshing")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: model.isRefreshing)
                }
                Spacer()
                Text("↵ select  ·  esc close")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
        .frame(width: 560, height: 420)
        .background(KeyEventHandler(onEscape: onClose, onReturn: {
            if let id = selectedId, let session = filtered.first(where: { $0.id == id }) {
                onSelect(session)
            } else if let first = filtered.first {
                onSelect(first)
            }
        }))
    }
}

// MARK: - Past session row

struct PastSessionRowView: View {
    let session: PastSession
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if session.isActive {
                            Circle()
                                .fill(Color(hex: "#22c55e"))
                                .frame(width: 6, height: 6)
                        }
                        Text(session.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Text(session.shortPath)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if session.isActive {
                            Text("active")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(hex: "#22c55e"))
                        } else {
                            Text(session.relativeDate)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !session.firstUserMessage.isEmpty {
                        Text(session.firstUserMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

// MARK: - macOS 13-compatible key event handler

private struct KeyEventHandler: NSViewRepresentable {
    let onEscape: () -> Void
    let onReturn: () -> Void

    func makeNSView(context: Context) -> KeyCatchView {
        let view = KeyCatchView()
        view.onEscape = onEscape
        view.onReturn = onReturn
        return view
    }

    func updateNSView(_ nsView: KeyCatchView, context: Context) {
        nsView.onEscape = onEscape
        nsView.onReturn = onReturn
    }
}

private class KeyCatchView: NSView {
    var onEscape: (() -> Void)?
    var onReturn: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onEscape?()
        case 36, 76: onReturn?()
        default: super.keyDown(with: event)
        }
    }
}
