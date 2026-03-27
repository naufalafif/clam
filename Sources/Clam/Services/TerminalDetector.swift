import AppKit
import Foundation

// MARK: - Terminal detection via process tree walking

/// Walks the ppid chain from a claude PID upward to find the hosting terminal app.
/// Works universally — any macOS GUI app in the chain is returned, no hardcoded list required.
/// Electron apps (VS Code, Termius, Obsidian, Cursor…) are handled by resolving the
/// main app from their Helper processes.
actor TerminalDetector {

    // Process names that are never the "terminal" — skip over these while walking
    private static let systemProcessNames: Set<String> = [
        "launchd", "kernel_task", "loginwindow", "WindowServer",
        "UserEventAgent", "corebrightnessd", "coreaudiod",
        "bash", "zsh", "fish", "sh", "dash",
        "login", "ssh", "tmux", "screen",
        "claude",
    ]

    // Display name overrides for known apps (optional cosmetic)
    private static let displayNames: [String: String] = [
        "com.mitchellh.ghostty": "Ghostty",
        "com.termius-dmg.mac": "Termius",
        "com.microsoft.VSCode": "VS Code",
        "com.todesktop.230313mzl4w4u9": "Cursor",
        "md.obsidian": "Obsidian",
        "com.googlecode.iterm2": "iTerm2",
        "com.apple.Terminal": "Terminal",
        "io.alacritty": "Alacritty",
        "com.github.wez.wezterm": "WezTerm",
        "net.kovidgoyal.kitty": "Kitty",
        "io.zed.Zed": "Zed",
        "co.warpdotdev.warp-terminal": "Warp",
        "com.hyper-is.hyper": "Hyper",
    ]

    func detect(claudePID: Int32) -> DetectedTerminal? {
        var pid = getParentPID(claudePID) ?? 0
        var depth = 0

        while pid > 1 && depth < 12 {
            let name = processName(for: pid).lowercased()

            // Skip shells and known system processes
            if !Self.systemProcessNames.contains(name) {
                // Try to find a registered macOS app for this PID
                if let app = NSRunningApplication(processIdentifier: pid) {
                    // Electron helper — resolve to main app
                    let resolved = resolveElectronApp(from: app) ?? app
                    let displayName = Self.displayNames[resolved.bundleIdentifier ?? ""]
                        ?? resolved.localizedName
                        ?? processName(for: resolved.processIdentifier)

                    return DetectedTerminal(
                        pid: resolved.processIdentifier,
                        name: displayName,
                        bundleIdentifier: resolved.bundleIdentifier
                    )
                }
            }

            pid = getParentPID(pid) ?? 0
            depth += 1
        }
        return nil
    }

    /// For Electron apps, the process in the chain is typically "App Helper (Renderer)".
    /// We find the main app by looking for a running app whose name matches without " Helper".
    private func resolveElectronApp(from helperApp: NSRunningApplication) -> NSRunningApplication? {
        guard let name = helperApp.localizedName, name.contains("Helper") else {
            return helperApp
        }
        // e.g. "Code Helper (Renderer)" → look for "Code" or "Visual Studio Code"
        let baseName = name
            .replacingOccurrences(of: " Helper.*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // Search running apps for the parent by bundle prefix or matching name
        let candidates = NSWorkspace.shared.runningApplications.filter { app in
            guard let appName = app.localizedName else { return false }
            return appName == baseName
                || appName.hasPrefix(baseName)
                || (helperApp.bundleIdentifier.map { bid in
                    let prefix = bid.components(separatedBy: ".").prefix(3).joined(separator: ".")
                    return app.bundleIdentifier?.hasPrefix(prefix) ?? false
                } ?? false)
        }
        // Prefer the one without "Helper" in its name
        return candidates.first { !($0.localizedName?.contains("Helper") ?? false) }
            ?? candidates.first
    }

    // MARK: - Low-level process helpers (sysctl)

    private func getParentPID(_ pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    private func processName(for pid: pid_t) -> String {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return "" }
        return withUnsafeBytes(of: info.kp_proc.p_comm) { ptr -> String in
            let bytes = ptr.bindMemory(to: CChar.self)
            guard let base = bytes.baseAddress else { return "" }
            return String(cString: base)
        }
    }
}

// MARK: - Activate helper

extension DetectedTerminal {
    @MainActor
    func activate() {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}
