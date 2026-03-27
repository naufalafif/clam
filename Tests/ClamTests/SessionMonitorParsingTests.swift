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
}
