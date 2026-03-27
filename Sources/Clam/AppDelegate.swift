import AppKit
import SwiftUI

// MARK: - Click-through hosting view

class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var statusView: ClickThroughHostingView<MenuBarView>?
    private var settingsWindow: NSWindow?
    private var searchPanel: SessionSearchPanelController?
    private var hasActivatedBefore = false

    let state = SessionState()

    private let sessionMonitor = SessionMonitor()
    private let usageMonitor = UsageMonitor()
    private let terminalLauncher = TerminalLauncher()

    private let sessionPollInterval: TimeInterval = 5
    private let usagePollInterval: TimeInterval = 60

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in self.setup() }
    }

    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in self.showSettings() }
        return false
    }

    // MARK: - Setup

    private func setup() {
        setupStatusItem()
        setupPopover()
        setupSearchPanel()
        startPolling()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover)
        button.target = self
        button.sendAction(on: .leftMouseDown)

        let view = ClickThroughHostingView(rootView: MenuBarView(activeCount: 0, fiveHourPct: 0, fiveHourReset: ""))
        view.frame = NSRect(x: 0, y: 0, width: 80, height: 22)
        button.addSubview(view)
        button.frame = view.frame
        statusItem.length = 80
        statusView = view
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 300)
        popover.behavior = .transient
        popover.animates = true
        // Set content once — state changes via @Published auto-update SwiftUI
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView(
                state: state,
                onFocusSession: { [weak self] session in self?.focusSession(session) },
                onOpenSearch: { [weak self] in self?.openSearch() },
                onRefresh: { [weak self] in
                    guard let self else { return }
                    self.state.isRefreshing = true
                    Task { [weak self] in
                        await self?.refreshSessions()
                        await self?.refreshUsage()
                    }
                },
                onSettings: { [weak self] in self?.showSettings() },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        )
    }

    private func setupSearchPanel() {
        searchPanel = SessionSearchPanelController(
            launcher: terminalLauncher,
            monitor: sessionMonitor
        )
    }

    // MARK: - Polling

    private func startPolling() {
        Task { await refreshSessions() }
        Task { await refreshUsage() }
        // Pre-warm past-session cache so first search open is instant
        Task { await searchPanel?.prewarm() }

        Task {
            while true {
                try? await Task.sleep(nanoseconds: UInt64(sessionPollInterval) * 1_000_000_000)
                await refreshSessions()
            }
        }
        Task {
            while true {
                try? await Task.sleep(nanoseconds: UInt64(usagePollInterval) * 1_000_000_000)
                await refreshUsage()
            }
        }
    }

    private func refreshSessions() async {
        let sessions = await sessionMonitor.fetchActiveSessions()
        state.activeSessions = sessions
        state.isSessionsLoaded = true
        updateStatusItem()
    }

    private func refreshUsage() async {
        state.isRefreshing = true
        let usage = await usageMonitor.fetchUsage()
        state.usageData = usage
        state.isUsageLoaded = true
        state.isRefreshing = false
        updateStatusItem()
    }

    // MARK: - Status item

    private func updateStatusItem() {
        let view = MenuBarView(
            activeCount: state.activeSessions.count,
            fiveHourPct: state.usageData.fiveHour.percentage,
            fiveHourReset: state.usageData.fiveHour.resetLabel
        )
        statusView?.rootView = view
        // Defer frame update to the next run loop cycle so the hosting view's
        // layout pass from the rootView change completes first.
        DispatchQueue.main.async { [weak self] in
            guard let self, let statusView = self.statusView else { return }
            let width = max(80, statusView.fittingSize.width + 8)
            statusView.frame = NSRect(x: 0, y: 0, width: width, height: 22)
            self.statusItem.button?.frame = statusView.frame
            self.statusItem.length = width
        }
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Sync popover size with the SwiftUI view's dynamic height
            if let hostingVC = popover.contentViewController as? NSHostingController<MenuContentView> {
                let size = hostingVC.view.fittingSize
                popover.contentSize = NSSize(width: 300, height: size.height)
            }
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Settings window

    func showSettings() {
        if popover.isShown { popover.performClose(nil) }

        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let win = NSWindow(contentViewController: hosting)
            win.title = "Clam"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 380, height: 260))
            win.setFrameAutosaveName("ClamSettings")
            settingsWindow = win
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: win, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.settingsWindow = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }

        guard let win = settingsWindow else { return }
        if !win.setFrameUsingName("ClamSettings"), let screen = NSScreen.main {
            let vis = screen.visibleFrame
            win.setFrameOrigin(NSPoint(x: vis.midX - 190, y: vis.midY - 130))
        }

        win.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)

        // Ice-style activation from accessory mode
        if !hasActivatedBefore {
            hasActivatedBefore = true
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.activate(ignoringOtherApps: true) }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Actions

    private func focusSession(_ session: ActiveSession) {
        popover.performClose(nil)
        session.terminal?.activate()
    }

    private func openSearch() {
        popover.performClose(nil)
        let preferred = TerminalLauncher.PreferredTerminal(
            rawValue: UserDefaults.standard.string(forKey: "preferredTerminal") ?? ""
        ) ?? .automatic
        searchPanel?.show(
            preferredTerminal: preferred,
            activeSessionIds: Set(state.activeSessions.map(\.sessionId))
        )
    }
}
