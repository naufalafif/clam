import Testing
import Foundation
@testable import ClamLib

@Suite("TerminalLauncher")
struct TerminalLauncherTests {
    let launcher = TerminalLauncher()

    // MARK: - shellEscape

    @Test("shellEscape wraps in single quotes")
    func shellEscapeSimple() async {
        let result = await launcher.shellEscape("/Users/test/project")
        #expect(result == "'/Users/test/project'")
    }

    @Test("shellEscape handles spaces")
    func shellEscapeSpaces() async {
        let result = await launcher.shellEscape("/Users/test/my project")
        #expect(result == "'/Users/test/my project'")
    }

    @Test("shellEscape handles embedded single quotes")
    func shellEscapeSingleQuote() async {
        let result = await launcher.shellEscape("/Users/test/it's here")
        #expect(result == "'/Users/test/it'\\''s here'")
    }

    @Test("shellEscape neutralizes command substitution")
    func shellEscapeCommandSubstitution() async {
        let result = await launcher.shellEscape("$(whoami)")
        #expect(result == "'$(whoami)'")
    }

    @Test("shellEscape neutralizes backtick injection")
    func shellEscapeBacktick() async {
        let result = await launcher.shellEscape("test`id`")
        #expect(result == "'test`id`'")
    }

    // MARK: - buildResumeCommand

    @Test("buildResumeCommand rejects invalid session ID")
    func rejectInvalidSessionId() async {
        let result = await launcher.buildResumeCommand(sessionId: "not-a-uuid", cwd: "/tmp")
        #expect(result == nil)
    }

    @Test("buildResumeCommand rejects shell injection attempt")
    func rejectShellInjection() async {
        let result = await launcher.buildResumeCommand(sessionId: "'; rm -rf / #", cwd: "/tmp")
        #expect(result == nil)
    }

    @Test("buildResumeCommand rejects empty session ID")
    func rejectEmptySessionId() async {
        let result = await launcher.buildResumeCommand(sessionId: "", cwd: "/tmp")
        #expect(result == nil)
    }

    @Test("buildResumeCommand accepts valid UUID and builds command")
    func acceptValidUUID() async {
        let uuid = "abcdef01-2345-6789-abcd-ef0123456789"
        let result = await launcher.buildResumeCommand(sessionId: uuid, cwd: "/tmp")
        #expect(result != nil)
        #expect(result?.sessionId == uuid)
        #expect(result?.cwd == "/tmp")
        #expect(result?.shellCmd.contains("--resume \(uuid)") == true)
        #expect(result?.shellCmd.contains("cd '/tmp'") == true)
    }

    // MARK: - buildAppleScript

    @Test("buildAppleScript for Terminal")
    func appleScriptTerminal() async {
        let cmd = "cd '/tmp' && 'claude' --resume abc"
        let script = await launcher.buildAppleScript(app: "Terminal", cmd: cmd)
        #expect(script.contains("tell application \"Terminal\""))
        #expect(script.contains("do script"))
        #expect(script.contains(cmd))
    }

    @Test("buildAppleScript for iTerm")
    func appleScriptiTerm() async {
        let cmd = "cd '/tmp' && 'claude' --resume abc"
        let script = await launcher.buildAppleScript(app: "iTerm", cmd: cmd)
        #expect(script.contains("tell application \"iTerm\""))
        #expect(script.contains("create window with default profile command"))
        #expect(script.contains(cmd))
    }

    // MARK: - PreferredTerminal

    @Test("PreferredTerminal bundle identifiers")
    func bundleIdentifiers() {
        #expect(TerminalLauncher.PreferredTerminal.automatic.bundleIdentifier == nil)
        #expect(TerminalLauncher.PreferredTerminal.ghostty.bundleIdentifier == "com.mitchellh.ghostty")
        #expect(TerminalLauncher.PreferredTerminal.iterm2.bundleIdentifier == "com.googlecode.iterm2")
        #expect(TerminalLauncher.PreferredTerminal.terminal.bundleIdentifier == "com.apple.Terminal")
        #expect(TerminalLauncher.PreferredTerminal.alacritty.bundleIdentifier == "io.alacritty")
        #expect(TerminalLauncher.PreferredTerminal.wezterm.bundleIdentifier == "com.github.wez.wezterm")
    }
}
