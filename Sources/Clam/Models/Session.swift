import AppKit
import Foundation

// MARK: - Active session (running claude process)

struct ActiveSession: Identifiable, Equatable {
    let pid: Int32
    let sessionId: String
    let cwd: String
    let startedAt: Date
    let name: String?
    let terminal: DetectedTerminal?

    var id: Int32 { pid }

    /// Display name: --name if set, otherwise last path component of cwd
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Short path: last 2 components (e.g. "Workspace/myproject")
    var shortPath: String {
        let url = URL(fileURLWithPath: cwd)
        let components = url.pathComponents
        guard components.count >= 2 else { return url.lastPathComponent }
        return components.suffix(2).joined(separator: "/")
    }

    static func == (lhs: ActiveSession, rhs: ActiveSession) -> Bool {
        lhs.pid == rhs.pid
    }
}

// MARK: - Terminal app detected for an active session

struct DetectedTerminal: Equatable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?

    static func == (lhs: DetectedTerminal, rhs: DetectedTerminal) -> Bool {
        lhs.pid == rhs.pid
    }
}

// MARK: - Past (non-active) session from JSONL history

struct PastSession: Identifiable {
    let sessionId: String
    let cwd: String
    let projectDir: String
    let lastMessageAt: Date
    let firstUserMessage: String
    var isActive: Bool = false
    var terminal: DetectedTerminal?

    var id: String { sessionId }

    var displayName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    var shortPath: String {
        let url = URL(fileURLWithPath: cwd)
        let components = url.pathComponents
        guard components.count >= 2 else { return url.lastPathComponent }
        return components.suffix(2).joined(separator: "/")
    }

    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastMessageAt, relativeTo: Date())
    }
}
