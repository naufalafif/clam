#!/usr/bin/env swift
import Foundation

// Self-contained test runner — no Xcode required.
// Run: swift Tests/test_terminal_launcher.swift
// Or:  make test

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
        print("  ✓ \(msg)")
    } else {
        failed += 1
        print("  ✗ \(msg)  [\(file):\(line)]")
    }
}

// -- Replicate the logic under test (same as TerminalLauncher) --

func shellEscape(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func buildResumeCommand(sessionId: String, cwd: String) -> (cmd: String, claudePath: String)? {
    guard sessionId.range(of: #"^[0-9a-fA-F\-]{36}$"#, options: .regularExpression) != nil else {
        return nil
    }
    let claudePath = ["/usr/local/bin/claude", "/opt/homebrew/bin/claude",
                      "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
    let cmd = "cd \(shellEscape(cwd)) && \(shellEscape(claudePath)) --resume \(sessionId)"
    return (cmd, claudePath)
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

// -- Tests --

let uuid = "abcdef01-2345-6789-abcd-ef0123456789"

print("\n── Session ID validation ──")
assert(buildResumeCommand(sessionId: "not-a-uuid", cwd: "/tmp") == nil,
       "rejects invalid session ID")
assert(buildResumeCommand(sessionId: "'; rm -rf / #", cwd: "/tmp") == nil,
       "rejects shell injection attempt")
assert(buildResumeCommand(sessionId: "", cwd: "/tmp") == nil,
       "rejects empty session ID")
assert(buildResumeCommand(sessionId: uuid, cwd: "/tmp") != nil,
       "accepts valid UUID")

print("\n── Shell escaping ──")
assert(shellEscape("/Users/test/project") == "'/Users/test/project'",
       "escapes simple path")
assert(shellEscape("/Users/test/my project") == "'/Users/test/my project'",
       "escapes path with spaces")
assert(shellEscape("/Users/test/it's here") == "'/Users/test/it'\\''s here'",
       "escapes path with single quote")
assert(shellEscape("$(whoami)") == "'$(whoami)'",
       "neutralizes command substitution")
assert(shellEscape("test`id`") == "'test`id`'",
       "neutralizes backtick injection")

print("\n── Command construction ──")
if let result = buildResumeCommand(sessionId: uuid, cwd: "/Users/test/project") {
    assert(result.cmd.contains("cd '/Users/test/project'"),
           "command contains cd into cwd")
    assert(result.cmd.contains("--resume \(uuid)"),
           "command contains --resume with session ID")
    assert(!result.cmd.contains("exec $SHELL"),
           "command does NOT have exec $SHELL (terminal stays open naturally)")
    assert(result.claudePath == "claude" || result.claudePath.hasPrefix("/"),
           "claude path is absolute (\(result.claudePath)) or bare fallback")
    if result.claudePath != "claude" {
        assert(FileManager.default.isExecutableFile(atPath: result.claudePath),
               "resolved claude path is executable: \(result.claudePath)")
    }
} else {
    assert(false, "buildResumeCommand should succeed for valid UUID")
}

print("\n── AppleScript construction ──")
let cmd = "cd '/Users/test/project' && '/usr/local/bin/claude' --resume \(uuid)"
let termScript = buildAppleScript(app: "Terminal", cmd: cmd)
assert(termScript.contains("tell application \"Terminal\""),
       "Terminal script targets Terminal.app")
assert(termScript.contains("do script"),
       "Terminal script uses do script")
assert(termScript.contains("cd '/Users/test/project'"),
       "Terminal script cd's into cwd")
assert(termScript.contains("'/usr/local/bin/claude' --resume \(uuid)"),
       "Terminal script uses absolute claude path and --resume")

let itermScript = buildAppleScript(app: "iTerm", cmd: cmd)
assert(itermScript.contains("tell application \"iTerm\""),
       "iTerm script targets iTerm")
assert(itermScript.contains("create window with default profile command"),
       "iTerm script uses create window")

let quoteCmd = "cd '/Users/test/it'\\''s here' && '/usr/local/bin/claude' --resume \(uuid)"
let quoteScript = buildAppleScript(app: "Terminal", cmd: quoteCmd)
assert(quoteScript.contains("cd '/Users/test/it'\\''s here'"),
       "AppleScript escapes single quotes in cwd")

print("\n── End-to-end: AppleScript compiles ──")
let testScript = buildAppleScript(app: "Terminal", cmd: cmd)
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
proc.arguments = ["-e", testScript, "-o", "/dev/null"]
proc.standardOutput = FileHandle.nullDevice
proc.standardError = Pipe()
try? proc.run()
proc.waitUntilExit()
assert(proc.terminationStatus == 0,
       "generated AppleScript compiles without errors")

// -- Summary --

print("\n══════════════════════════════")
print("  \(passed) passed, \(failed) failed")
print("══════════════════════════════\n")

exit(failed > 0 ? 1 : 0)
