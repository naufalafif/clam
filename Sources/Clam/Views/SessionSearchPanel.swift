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
        let cacheById = Dictionary(uniqueKeysWithValues: sessionCache.map { ($0.sessionId, $0) })
        let activeAsPast = activeSessions.map { session -> PastSession in
            let cached = cacheById[session.sessionId]
            return PastSession(
                sessionId: session.sessionId,
                cwd: session.cwd,
                projectDir: cached?.projectDir ?? "",
                lastMessageAt: session.startedAt,
                firstUserMessage: cached?.firstUserMessage ?? "",
                isActive: true,
                terminal: session.terminal,
                filePath: cached?.filePath ?? "",
                searchBlob: cached?.searchBlob ?? ""
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
            let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.sessionId, $0) })
            let enrichedActive = activeSessions.map { session -> PastSession in
                let cached = byId[session.sessionId]
                return PastSession(
                    sessionId: session.sessionId,
                    cwd: session.cwd,
                    projectDir: cached?.projectDir ?? "",
                    lastMessageAt: session.startedAt,
                    firstUserMessage: cached?.firstUserMessage ?? "",
                    isActive: true,
                    terminal: session.terminal,
                    filePath: cached?.filePath ?? "",
                    searchBlob: cached?.searchBlob ?? ""
                )
            }
            let pastFiltered = all.filter { !activeSessionIds.contains($0.sessionId) }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                model.sessions = enrichedActive + pastFiltered
                model.isLoading = false
                model.isRefreshing = false
            }
        }
    }

    private func presentPanel(preferredTerminal: TerminalLauncher.PreferredTerminal) {
        let view = SessionSearchView(
            model: model,
            monitor: monitor,
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
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 480),
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
            p.setFrameOrigin(NSPoint(x: vis.midX - 430, y: vis.midY - 140))
        }

        panel = p
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SwiftUI search view

struct SessionSearchView: View {
    @ObservedObject var model: SessionSearchModel
    let monitor: SessionMonitor
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
                || $0.searchBlob.contains(q)
        }
    }

    private var selectedSession: PastSession? {
        guard let id = selectedId else { return nil }
        return filtered.first(where: { $0.id == id })
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

            HStack(spacing: 0) {
                Group {
                    if model.isLoading {
                        VStack {
                            Spacer()
                            ProgressView("Loading sessions…")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else if filtered.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "tray")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text(query.isEmpty ? "No past sessions found" : "No results for \"\(query)\"")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filtered) { session in
                                    PastSessionRowView(
                                        session: session,
                                        isSelected: selectedId == session.id
                                    ) { selectedId = session.id }
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
                .frame(width: 360)
                .frame(maxHeight: .infinity)

                Divider()

                ConversationPreview(
                    session: selectedSession,
                    monitor: monitor,
                    query: query,
                    onOpen: { onSelect($0) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text("click to preview  ·  ↵ open  ·  esc close")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
        }
        .frame(width: 860, height: 480)
        .background(KeyEventHandler(onEscape: onClose, onReturn: {
            if let session = selectedSession { onSelect(session) }
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

// MARK: - Right-side preview pane showing the selected session's full conversation

struct ConversationPreview: View {
    let session: PastSession?
    let monitor: SessionMonitor
    let query: String
    let onOpen: (PastSession) -> Void

    @State private var messages: [ConversationMessage] = []
    @State private var isLoading = false
    @State private var loadedSessionId: String?

    var body: some View {
        Group {
            if let session {
                content(for: session)
            } else {
                placeholder("Select a session to preview its conversation")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
    }

    @ViewBuilder
    private func content(for session: PastSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if session.isActive {
                        Circle().fill(Color(hex: "#22c55e")).frame(width: 6, height: 6)
                    }
                    Text(session.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(session.isActive ? "active" : session.relativeDate)
                        .font(.system(size: 11))
                        .foregroundStyle(session.isActive ? Color(hex: "#22c55e") : .secondary)
                    Spacer()
                    Button(action: { onOpen(session) }) {
                        HStack(spacing: 4) {
                            Image(systemName: session.isActive ? "arrow.up.right.square" : "play.fill")
                                .font(.system(size: 10))
                            Text(session.isActive ? "Focus" : "Resume")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                Text(session.cwd)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if isLoading && messages.isEmpty {
                Spacer()
                HStack { Spacer(); ProgressView().scaleEffect(0.7); Spacer() }
                Spacer()
            } else if messages.isEmpty {
                Spacer()
                Text("No messages")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { msg in
                                MessageBubble(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
        .task(id: session.id) { await load(session) }
    }

    @ViewBuilder
    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
    }

    private func load(_ session: PastSession) async {
        guard loadedSessionId != session.id else { return }
        guard !session.filePath.isEmpty else {
            messages = []
            loadedSessionId = session.id
            return
        }
        isLoading = true
        let path = session.filePath
        let loaded = await monitor.loadConversation(filePath: path)
        if Task.isCancelled { return }
        messages = loaded
        loadedSessionId = session.id
        isLoading = false
    }
}

private struct MessageBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 2) {
                Text(message.role == .user ? "You" : "Claude")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(message.role == .user
                          ? Color.accentColor.opacity(0.15)
                          : Color.secondary.opacity(0.10))
            )
            if message.role == .assistant { Spacer(minLength: 40) }
        }
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
