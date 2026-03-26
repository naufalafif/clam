import AppKit
import Foundation

// MARK: - Launch a terminal with claude --resume <sessionId>

actor TerminalLauncher {

    enum PreferredTerminal: String, CaseIterable, Identifiable {
        case automatic = "Automatic"
        case ghostty   = "Ghostty"
        case iterm2    = "iTerm2"
        case terminal  = "Terminal"
        case alacritty = "Alacritty"
        case wezterm   = "WezTerm"

        var id: String { rawValue }

        var bundleIdentifier: String? {
            switch self {
            case .ghostty:   return "com.mitchellh.ghostty"
            case .iterm2:    return "com.googlecode.iterm2"
            case .terminal:  return "com.apple.Terminal"
            case .alacritty: return "io.alacritty"
            case .wezterm:   return "com.github.wez.wezterm"
            case .automatic: return nil
            }
        }

        var isInstalled: Bool {
            if self == .automatic { return true }
            guard let bid = bundleIdentifier else { return false }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil
        }

        static var installed: [PreferredTerminal] {
            allCases.filter(\.isInstalled)
        }
    }

    func resume(sessionId: String, cwd: String, preferred: PreferredTerminal) {
        // SECURITY: validate sessionId is a UUID — prevents command/AppleScript injection
        guard sessionId.range(of: #"^[0-9a-fA-F\-]{36}$"#, options: .regularExpression) != nil else {
            return
        }

        let terminal = resolveTerminal(preferred: preferred)
        let claudePath = findClaude() ?? "claude"

        // Pass args as array — no shell interpolation, no injection
        switch terminal {
        case .ghostty:
            launchCLI(bundleId: "com.mitchellh.ghostty", binaryName: "ghostty",
                      args: ["-e", claudePath, "--resume", sessionId])
        case .alacritty:
            launchCLI(bundleId: "io.alacritty", binaryName: "alacritty",
                      args: ["-e", claudePath, "--resume", sessionId])
        case .wezterm:
            launchCLI(bundleId: "com.github.wez.wezterm", binaryName: "wezterm",
                      args: ["start", "--", claudePath, "--resume", sessionId])
        case .iterm2:
            launchViaAppleScript(app: "iTerm", sessionId: sessionId)
        case .terminal, .automatic:
            launchViaAppleScript(app: "Terminal", sessionId: sessionId)
        }
    }

    // MARK: - Private

    private func findClaude() -> String? {
        ["/usr/local/bin/claude", "/opt/homebrew/bin/claude",
         "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func resolveTerminal(preferred: PreferredTerminal) -> PreferredTerminal {
        if preferred != .automatic { return preferred }
        let order: [PreferredTerminal] = [.ghostty, .iterm2, .alacritty, .wezterm, .terminal]
        return order.first(where: \.isInstalled) ?? .terminal
    }

    private func launchCLI(bundleId: String, binaryName: String, args: [String]) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let binary = appURL.appendingPathComponent("Contents/MacOS/\(binaryName)")
            if FileManager.default.isExecutableFile(atPath: binary.path) {
                launchProcess(binary.path, args: args)
                return
            }
        }

        let paths = ["/opt/homebrew/bin/\(binaryName)", "/usr/local/bin/\(binaryName)"]
        if let found = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            launchProcess(found, args: args)
            return
        }

        // Fallback to Terminal.app via AppleScript
        launchViaAppleScript(app: "Terminal", sessionId: args.last ?? "")
    }

    private func launchProcess(_ path: String, args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    /// SECURITY: sessionId is pre-validated as UUID (alphanumeric + hyphens only)
    /// so it's safe to interpolate into AppleScript. No shell metacharacters possible.
    private func launchViaAppleScript(app: String, sessionId: String) {
        let script: String
        if app == "iTerm" {
            script = """
            tell application "iTerm"
                activate
                create window with default profile command "claude --resume \(sessionId)"
            end tell
            """
        } else {
            script = """
            tell application "Terminal"
                activate
                do script "claude --resume \(sessionId)"
            end tell
            """
        }

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
