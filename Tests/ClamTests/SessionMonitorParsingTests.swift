import Testing
import Foundation
@testable import ClamLib

@Suite("SessionMonitor parsing")
struct SessionMonitorParsingTests {

    @Test("parsePastSessionData extracts session metadata and first user message")
    func basicParse() {
        let lines = [
            #"{"sessionId":"abc-123","cwd":"/Users/test/project"}"#,
            #"{"type":"user","message":{"content":"Hello world"}}"#,
        ]
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)

        let result = SessionMonitor.parsePastSessionData(
            data, fileModificationDate: Date(), projectDir: "/projects/test"
        )
        #expect(result != nil)
        #expect(result?.sessionId == "abc-123")
        #expect(result?.cwd == "/Users/test/project")
        #expect(result?.firstUserMessage == "Hello world")
        #expect(result?.projectDir == "/projects/test")
    }

    @Test("parsePastSessionData skips XML-prefixed user messages")
    func skipXmlMessages() {
        let lines = [
            #"{"sessionId":"abc","cwd":"/tmp"}"#,
            #"{"type":"user","message":{"content":"<context>system prompt</context>"}}"#,
            #"{"type":"user","message":{"content":"Real user message"}}"#,
        ]
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)

        let result = SessionMonitor.parsePastSessionData(
            data, fileModificationDate: Date(), projectDir: "/p"
        )
        #expect(result?.firstUserMessage == "Real user message")
    }

    @Test("parsePastSessionData returns nil for empty data")
    func emptyData() {
        let result = SessionMonitor.parsePastSessionData(
            Data(), fileModificationDate: Date(), projectDir: "/p"
        )
        #expect(result == nil)
    }

    @Test("parsePastSessionData returns nil for missing sessionId")
    func missingSessionId() {
        let data = Data(("{\"cwd\":\"/tmp\"}\n").utf8)
        let result = SessionMonitor.parsePastSessionData(
            data, fileModificationDate: Date(), projectDir: "/p"
        )
        #expect(result == nil)
    }

    @Test("parsePastSessionData truncates long messages to 120 chars")
    func truncatesLongMessage() {
        let longMsg = String(repeating: "a", count: 200)
        let lines = [
            #"{"sessionId":"abc","cwd":"/tmp"}"#,
            "{\"type\":\"user\",\"message\":{\"content\":\"\(longMsg)\"}}",
        ]
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)

        let result = SessionMonitor.parsePastSessionData(
            data, fileModificationDate: Date(), projectDir: "/p"
        )
        #expect(result?.firstUserMessage.count == 120)
    }

    @Test("parsePastSessionData preserves file modification date")
    func preservesModificationDate() {
        let mtime = Date(timeIntervalSince1970: 1_700_000_000)
        let data = Data(("{\"sessionId\":\"abc\",\"cwd\":\"/tmp\"}\n").utf8)

        let result = SessionMonitor.parsePastSessionData(
            data, fileModificationDate: mtime, projectDir: "/p"
        )
        #expect(result?.lastMessageAt == mtime)
    }

    @Test("parsePastSessionData defaults firstUserMessage to empty string")
    func defaultsEmptyMessage() {
        let data = Data(("{\"sessionId\":\"abc\",\"cwd\":\"/tmp\"}\n").utf8)

        let result = SessionMonitor.parsePastSessionData(
            data, fileModificationDate: Date(), projectDir: "/p"
        )
        #expect(result?.firstUserMessage == "")
    }

    // MARK: - extractNameFlag (KERN_PROCARGS2 byte scanner)

    @Test("extractNameFlag finds --name <value>")
    func nameFlagSpaceForm() {
        let buf = makeProcArgs(
            execPath: "/usr/local/bin/claude",
            argv: ["claude", "--name", "Project X", "--resume", "abc-123"]
        )
        let result = buf.withUnsafeBytes { SessionMonitor.extractNameFlag(from: $0) }
        #expect(result == "Project X")
    }

    @Test("extractNameFlag finds --name=value")
    func nameFlagEqualForm() {
        let buf = makeProcArgs(
            execPath: "/usr/local/bin/claude",
            argv: ["claude", "--name=Hello", "--resume"]
        )
        let result = buf.withUnsafeBytes { SessionMonitor.extractNameFlag(from: $0) }
        #expect(result == "Hello")
    }

    @Test("extractNameFlag returns nil when no --name flag")
    func noNameFlag() {
        let buf = makeProcArgs(
            execPath: "/usr/local/bin/claude",
            argv: ["claude", "--resume", "abc-123"]
        )
        let result = buf.withUnsafeBytes { SessionMonitor.extractNameFlag(from: $0) }
        #expect(result == nil)
    }

    @Test("extractNameFlag returns nil for buffer too small")
    func tooSmall() {
        let buf: [UInt8] = [1, 2, 3]
        let result = buf.withUnsafeBytes { SessionMonitor.extractNameFlag(from: $0) }
        #expect(result == nil)
    }

    @Test("extractNameFlag returns nil when --name is the last arg with no value")
    func nameWithoutValue() {
        let buf = makeProcArgs(
            execPath: "/usr/local/bin/claude",
            argv: ["claude", "--name"]
        )
        let result = buf.withUnsafeBytes { SessionMonitor.extractNameFlag(from: $0) }
        #expect(result == nil)
    }

    @Test("extractNameFlag does not match --names or --namespace")
    func similarFlagsNotMatched() {
        let buf = makeProcArgs(
            execPath: "/usr/local/bin/claude",
            argv: ["claude", "--names", "foo", "--namespace=bar"]
        )
        let result = buf.withUnsafeBytes { SessionMonitor.extractNameFlag(from: $0) }
        #expect(result == nil)
    }
}

/// Build a synthetic `KERN_PROCARGS2` buffer for testing.
/// Layout: int32 argc; exec_path NUL; one alignment NUL; argv strings; envp strings.
private func makeProcArgs(execPath: String, argv: [String], envp: [String] = []) -> [UInt8] {
    var bytes: [UInt8] = []
    let argc = Int32(argv.count)
    withUnsafeBytes(of: argc.littleEndian) { bytes.append(contentsOf: $0) }
    bytes.append(contentsOf: execPath.utf8)
    bytes.append(0)
    bytes.append(0) // alignment NUL — real macOS uses variable padding; one NUL is enough for the scanner
    for arg in argv {
        bytes.append(contentsOf: arg.utf8)
        bytes.append(0)
    }
    for env in envp {
        bytes.append(contentsOf: env.utf8)
        bytes.append(0)
    }
    return bytes
}
