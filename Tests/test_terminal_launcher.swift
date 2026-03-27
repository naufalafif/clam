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

func buildResumeCommand(sessionId: String, cwd: String) -> (shellCmd: String, claudePath: String)? {
    guard sessionId.range(of: #"^[0-9a-fA-F\-]{36}$"#, options: .regularExpression) != nil else {
        return nil
    }
    let claudePath = ["/usr/local/bin/claude", "/opt/homebrew/bin/claude",
                      "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
    let shellCmd = "cd \(shellEscape(cwd)) && \(shellEscape(claudePath)) --resume \(sessionId); exec $SHELL"
    return (shellCmd, claudePath)
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

print("\n── Shell command construction ──")
if let result = buildResumeCommand(sessionId: uuid, cwd: "/Users/test/project") {
    assert(result.shellCmd.contains("cd '/Users/test/project'"),
           "shell command contains cd into cwd")
    assert(result.shellCmd.contains("--resume \(uuid)"),
           "shell command contains --resume with session ID")
    assert(result.shellCmd.contains("exec $SHELL"),
           "shell command keeps window open with exec $SHELL")
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
let termScript = buildAppleScript(app: "Terminal", claudePath: "/usr/local/bin/claude",
                                   sessionId: uuid, cwd: "/Users/test/project")
assert(termScript.contains("tell application \"Terminal\""),
       "Terminal script targets Terminal.app")
assert(termScript.contains("do script"),
       "Terminal script uses do script")
assert(termScript.contains("cd '/Users/test/project'"),
       "Terminal script cd's into cwd")
assert(termScript.contains("'/usr/local/bin/claude' --resume \(uuid)"),
       "Terminal script uses absolute claude path and --resume")

let itermScript = buildAppleScript(app: "iTerm", claudePath: "/usr/local/bin/claude",
                                    sessionId: uuid, cwd: "/tmp")
assert(itermScript.contains("tell application \"iTerm\""),
       "iTerm script targets iTerm")
assert(itermScript.contains("create window with default profile command"),
       "iTerm script uses create window")

let quoteScript = buildAppleScript(app: "Terminal", claudePath: "/usr/local/bin/claude",
                                    sessionId: uuid, cwd: "/Users/test/it's here")
assert(quoteScript.contains("cd '/Users/test/it'\\''s here'"),
       "AppleScript escapes single quotes in cwd")

print("\n── End-to-end: AppleScript is valid (compiles) ──")
let testScript = buildAppleScript(app: "Terminal", claudePath: "/usr/local/bin/claude",
                                   sessionId: uuid, cwd: "/Users/test/project")
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
