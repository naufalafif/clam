import Testing
import Foundation
@testable import ClamLib

@Suite("ActiveSession")
struct ActiveSessionTests {

    @Test("displayName prefers name over cwd")
    func displayNameWithName() {
        let s = ActiveSession(pid: 1, sessionId: "abc", cwd: "/Users/test/project",
                              startedAt: Date(), name: "my-session", terminal: nil)
        #expect(s.displayName == "my-session")
    }

    @Test("displayName falls back to last path component when name is nil")
    func displayNameNilName() {
        let s = ActiveSession(pid: 1, sessionId: "abc", cwd: "/Users/test/project",
                              startedAt: Date(), name: nil, terminal: nil)
        #expect(s.displayName == "project")
    }

    @Test("displayName falls back when name is empty string")
    func displayNameEmptyName() {
        let s = ActiveSession(pid: 1, sessionId: "abc", cwd: "/Users/test/project",
                              startedAt: Date(), name: "", terminal: nil)
        #expect(s.displayName == "project")
    }

    @Test("shortPath returns last 2 components")
    func shortPath() {
        let s = ActiveSession(pid: 1, sessionId: "abc", cwd: "/Users/test/deep/project",
                              startedAt: Date(), name: nil, terminal: nil)
        #expect(s.shortPath == "deep/project")
    }

    @Test("shortPath with 2-component path")
    func shortPathMinimal() {
        let s = ActiveSession(pid: 1, sessionId: "abc", cwd: "/Users/project",
                              startedAt: Date(), name: nil, terminal: nil)
        #expect(s.shortPath == "Users/project")
    }

    @Test("equality is based on pid")
    func equality() {
        let a = ActiveSession(pid: 42, sessionId: "a", cwd: "/a", startedAt: Date(), name: nil, terminal: nil)
        let b = ActiveSession(pid: 42, sessionId: "b", cwd: "/b", startedAt: Date(), name: "x", terminal: nil)
        #expect(a == b)
    }
}

@Suite("PastSession")
struct PastSessionTests {

    @Test("displayName from cwd last path component")
    func displayName() {
        let s = PastSession(sessionId: "abc", cwd: "/Users/test/myproject",
                            projectDir: "/dir", lastMessageAt: Date(), firstUserMessage: "hello")
        #expect(s.displayName == "myproject")
    }

    @Test("shortPath returns last 2 components")
    func shortPath() {
        let s = PastSession(sessionId: "abc", cwd: "/Users/test/myproject",
                            projectDir: "/dir", lastMessageAt: Date(), firstUserMessage: "")
        #expect(s.shortPath == "test/myproject")
    }

    @Test("relativeDate produces non-empty string")
    func relativeDate() {
        let past = Date().addingTimeInterval(-3600)
        let s = PastSession(sessionId: "abc", cwd: "/tmp", projectDir: "/dir",
                            lastMessageAt: past, firstUserMessage: "")
        #expect(!s.relativeDate.isEmpty)
    }
}
