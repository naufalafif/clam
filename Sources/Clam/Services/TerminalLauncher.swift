import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "com.naufal.clam", category: "TerminalLauncher")

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
        logger.info("resume: sessionId=\(sessionId) cwd=\(cwd) preferred=\(preferred.rawValue)")

        // SECURITY: validate sessionId is a UUID — prevents command/AppleScript injection
        guard sessionId.range(of: #"^[0-9a-fA-F\-]{36}$"#, options: .regularExpression) != nil else {
            logger.error("resume: invalid sessionId rejected")
            return
        }

        let terminal = resolveTerminal(preferred: preferred)
        let claudePath = findClaude() ?? "claude"
        let cmd = "cd \(shellEscape(cwd)) && \(shellEscape(claudePath)) --resume \(sessionId)"
        logger.info("resume: resolved terminal=\(terminal.rawValue) claude=\(claudePath)")
        logger.info("resume: cmd=\(cmd)")

        // Use AppleScript to launch — it's the only reliable way to get a real
        // TTY on macOS. Process-based launching pipes stdout/stderr to /dev/null
        // which breaks claude's TUI. Ghostty/Alacritty/WezTerm don't support
        // AppleScript or reliable CLI launching on macOS, so we fall back to
        // Terminal.app for those.
        switch terminal {
        case .iterm2:
            launchViaAppleScript(app: "iTerm", cmd: cmd)
        default:
            launchViaAppleScript(app: "Terminal", cmd: cmd)
        }
    }

    // MARK: - Command building (internal for testing)

    struct ResumeCommand {
        let shellCmd: String
        let claudePath: String
        let cwd: String
        let sessionId: String
    }

    func buildResumeCommand(sessionId: String, cwd: String) -> ResumeCommand? {
        guard sessionId.range(of: #"^[0-9a-fA-F\-]{36}$"#, options: .regularExpression) != nil else {
            return nil
        }
        let claudePath = findClaude() ?? "claude"
        let shellCmd = "cd \(shellEscape(cwd)) && \(shellEscape(claudePath)) --resume \(sessionId)"
        return ResumeCommand(shellCmd: shellCmd, claudePath: claudePath, cwd: cwd, sessionId: sessionId)
    }

    func buildAppleScript(app: String, cmd: String) -> String {
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

    private func debugLog(_ msg: String) {
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/clam/debug.log")
        let entry = "[\(Date())] \(msg)\n"
        if let data = entry.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logPath)
            }
        }
    }

    /// Shell-escape a string by wrapping in single quotes
    func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Launch via AppleScript — works for Terminal.app and iTerm2.
    /// These apps have native AppleScript support for running commands.
    private func launchViaAppleScript(app: String, cmd: String) {
        let script = buildAppleScript(app: app, cmd: cmd)
        logger.info("launchViaAppleScript: app=\(app)")
        logger.debug("launchViaAppleScript: script=\(script)")
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                logger.error("AppleScript error: \(error)")
                debugLog("AppleScript ERROR: \(error)\nScript: \(script)")
            } else {
                logger.info("AppleScript executed successfully")
                debugLog("AppleScript OK for app=\(app)")
            }
        } else {
            logger.error("Failed to create NSAppleScript")
        }
    }
}
