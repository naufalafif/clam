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

        // Build a shell command that cd's into the project and resumes.
        // Uses login shell (-l) so the user's full PATH/env is available.
        // The trailing `; exec $SHELL` keeps the window open if claude exits.
        let shellCmd = "cd \(shellEscape(cwd)) && \(shellEscape(claudePath)) --resume \(sessionId); exec $SHELL"

        switch terminal {
        case .ghostty:
            launchCLI(bundleId: "com.mitchellh.ghostty", binaryName: "ghostty",
                      args: ["-e", "/bin/zsh", "-l", "-c", shellCmd], cwd: cwd, claudePath: claudePath)
        case .alacritty:
            launchCLI(bundleId: "io.alacritty", binaryName: "alacritty",
                      args: ["-e", "/bin/zsh", "-l", "-c", shellCmd], cwd: cwd, claudePath: claudePath)
        case .wezterm:
            launchCLI(bundleId: "com.github.wez.wezterm", binaryName: "wezterm",
                      args: ["start", "--cwd", cwd, "--", "/bin/zsh", "-l", "-c", shellCmd], cwd: cwd, claudePath: claudePath)
        case .iterm2:
            launchViaAppleScript(app: "iTerm", claudePath: claudePath, sessionId: sessionId, cwd: cwd)
        case .terminal, .automatic:
            launchViaAppleScript(app: "Terminal", claudePath: claudePath, sessionId: sessionId, cwd: cwd)
        }
    }

    // MARK: - Command building (internal for testing)

    struct ResumeCommand {
        let shellCmd: String       // full shell command string
        let claudePath: String     // resolved absolute path to claude
        let cwd: String
        let sessionId: String
    }

    func buildResumeCommand(sessionId: String, cwd: String) -> ResumeCommand? {
        guard sessionId.range(of: #"^[0-9a-fA-F\-]{36}$"#, options: .regularExpression) != nil else {
            return nil
        }
        let claudePath = findClaude() ?? "claude"
        let shellCmd = "cd \(shellEscape(cwd)) && \(shellEscape(claudePath)) --resume \(sessionId); exec $SHELL"
        return ResumeCommand(shellCmd: shellCmd, claudePath: claudePath, cwd: cwd, sessionId: sessionId)
    }

    func buildAppleScript(app: String, claudePath: String, sessionId: String, cwd: String) -> String {
        let cmd = "cd \(shellEscape(cwd)) && \(shellEscape(claudePath)) --resume \(sessionId)"
        if app == "iTerm" {
            return """
            tell application "iTerm"
                activate
                create window with default profile command "\(cmd)"
            end tell
            """
        } else {
            return """
            tell application "Terminal"
                activate
                do script "\(cmd)"
            end tell
            """
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

    private func launchCLI(bundleId: String, binaryName: String, args: [String], cwd: String, claudePath: String) {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let binary = appURL.appendingPathComponent("Contents/MacOS/\(binaryName)")
            if FileManager.default.isExecutableFile(atPath: binary.path) {
                launchProcess(binary.path, args: args, cwd: cwd)
                return
            }
        }

        let paths = ["/opt/homebrew/bin/\(binaryName)", "/usr/local/bin/\(binaryName)"]
        if let found = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            launchProcess(found, args: args, cwd: cwd)
            return
        }

        // Fallback to Terminal.app via AppleScript
        launchViaAppleScript(app: "Terminal", claudePath: claudePath, sessionId: args.last ?? "", cwd: cwd)
    }

    private func launchProcess(_ path: String, args: [String], cwd: String? = nil) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        if let cwd, FileManager.default.fileExists(atPath: cwd) {
            task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    /// Shell-escape a string by wrapping in single quotes
    func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func launchViaAppleScript(app: String, claudePath: String, sessionId: String, cwd: String) {
        let script = buildAppleScript(app: app, claudePath: claudePath, sessionId: sessionId, cwd: cwd)
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
