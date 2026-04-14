import Foundation

// MARK: - Session state (main-actor observable)

@MainActor
class SessionState: ObservableObject {
    @Published var activeSessions: [ActiveSession] = []
    @Published var usageData: UsageData = .empty
    @Published var isRefreshing: Bool = false
    /// True once the first session poll has completed
    @Published var isSessionsLoaded: Bool = false
    /// True once the first usage fetch has completed
    @Published var isUsageLoaded: Bool = false
}

// MARK: - Reads active sessions from ~/.claude/sessions/ + verifies PIDs are alive

actor SessionMonitor {
    private let detector = TerminalDetector()
    private let claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude")

    func fetchActiveSessions() async -> [ActiveSession] {
        let pids = aliveClaudioPIDs()
        var sessions: [ActiveSession] = []

        for pid in pids {
            let sessionFile = claudeDir.appendingPathComponent("sessions/\(pid).json")
            guard let data = try? Data(contentsOf: sessionFile),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            guard let sessionId = json["sessionId"] as? String,
                  let cwd = json["cwd"] as? String
            else { continue }

            let startedAt: Date
            if let ms = json["startedAt"] as? Double {
                startedAt = Date(timeIntervalSince1970: ms / 1000)
            } else {
                startedAt = Date()
            }

            let name = json["name"] as? String ?? parseSessionName(pid: pid)
            let terminal = await detector.detect(claudePID: pid)

            sessions.append(ActiveSession(
                pid: pid,
                sessionId: sessionId,
                cwd: cwd,
                startedAt: startedAt,
                name: name,
                terminal: terminal
            ))
        }

        return sessions.sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Past sessions from JSONL project files

    func fetchPastSessions() -> [PastSession] {
        let projectsDir = claudeDir.appendingPathComponent("projects")
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        var sessions: [PastSession] = []

        for projectDir in projectDirs {
            guard let jsonlFiles = try? FileManager.default.contentsOfDirectory(
                at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in jsonlFiles where file.pathExtension == "jsonl" {
                if let session = parsePastSession(from: file, projectDir: projectDir.path) {
                    sessions.append(session)
                }
            }
        }

        return sessions.sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    // MARK: - Private helpers

    /// Read all *.json files in ~/.claude/sessions/ and verify the PID is still alive.
    /// This avoids running `ps` which can behave differently inside an app bundle.
    private func aliveClaudioPIDs() -> [Int32] {
        let sessionsDir = claudeDir.appendingPathComponent("sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Int32? in
                guard let pid = Int32(url.deletingPathExtension().lastPathComponent) else { return nil }
                // kill(pid, 0) returns 0 if process exists, -1 if not
                return kill(pid, 0) == 0 ? pid : nil
            }
    }

    private func parseSessionName(pid: Int32) -> String? {
        // Read args via sysctl to avoid spawning a subprocess
        var argmax = 0
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var size = MemoryLayout<Int>.stride
        sysctl(&mib, 2, &argmax, &size, nil, 0)

        var args = [CChar](repeating: 0, count: argmax)
        var argsSize = argmax
        var mib2: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib2, 3, &args, &argsSize, nil, 0) == 0 else { return nil }

        let raw = args.withUnsafeBufferPointer { ptr -> String in
            String(bytes: ptr.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
        }

        // Look for --name flag
        let parts = raw.components(separatedBy: "\0").filter { !$0.isEmpty }
        for (i, part) in parts.enumerated() {
            if part == "--name", i + 1 < parts.count {
                return parts[i + 1]
            }
            if part.hasPrefix("--name=") {
                return String(part.dropFirst("--name=".count))
            }
        }
        return nil
    }

    // MARK: - Parsing helper (internal for testing)

    /// Parse JSONL session data from raw bytes.
    /// Reads up to 15 lines to extract sessionId, cwd, and first user message.
    static func parsePastSessionData(
        _ data: Data,
        fileModificationDate: Date,
        projectDir: String
    ) -> PastSession? {
        var sessionId: String?
        var cwd: String?
        var firstUserMessage: String?
        var linesRead = 0
        var startIndex = data.startIndex

        while linesRead < 15, startIndex < data.endIndex {
            guard let newline = data[startIndex...].firstIndex(of: UInt8(ascii: "\n")) else {
                // Handle last line without trailing newline
                let lineData = data[startIndex...]
                if !lineData.isEmpty { linesRead += 1 }
                if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    if sessionId == nil {
                        sessionId = json["sessionId"] as? String
                        cwd = json["cwd"] as? String
                    }
                    if firstUserMessage == nil,
                       json["type"] as? String == "user",
                       let msg = json["message"] as? [String: Any],
                       let text = msg["content"] as? String,
                       !text.hasPrefix("<") {
                        firstUserMessage = String(text.prefix(120))
                    }
                }
                break
            }

            let lineData = data[startIndex..<newline]
            startIndex = data.index(after: newline)
            linesRead += 1

            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            if sessionId == nil {
                sessionId = json["sessionId"] as? String
                cwd = json["cwd"] as? String
            }

            if firstUserMessage == nil,
               json["type"] as? String == "user",
               let msg = json["message"] as? [String: Any],
               let text = msg["content"] as? String,
               !text.hasPrefix("<") {
                firstUserMessage = String(text.prefix(120))
            }
        }

        guard let sid = sessionId, let dir = cwd else { return nil }

        return PastSession(
            sessionId: sid,
            cwd: dir,
            projectDir: projectDir,
            lastMessageAt: fileModificationDate,
            firstUserMessage: firstUserMessage ?? ""
        )
    }

    /// Fast parse: reads the first 15 lines for metadata + first message, then scans the
    /// remainder of the file (capped) to build a lowercased full-text search blob.
    private func parsePastSession(from file: URL, projectDir: String) -> PastSession? {
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast

        // Cap total read at 1MB per session file to bound startup cost.
        let maxBytes = 1_000_000
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(min(maxBytes, 64 * 1024))
        while buffer.count < maxBytes {
            let chunk = handle.readData(ofLength: 32 * 1024)
            if chunk.isEmpty { break }
            buffer.append(chunk)
        }

        // If we hit the cap mid-line, trim to the last complete line so JSON parse doesn't choke.
        if buffer.count == maxBytes, let lastNewline = buffer.lastIndex(of: UInt8(ascii: "\n")) {
            buffer = buffer.prefix(through: lastNewline)
        }

        guard var session = Self.parsePastSessionData(buffer, fileModificationDate: mtime, projectDir: projectDir) else {
            return nil
        }
        session.filePath = file.path
        session.searchBlob = Self.buildSearchBlob(from: buffer)
        return session
    }

    /// Concatenate all user/assistant message text across the buffer, lowercased and
    /// truncated per-message, to serve as a search index.
    static func buildSearchBlob(from data: Data) -> String {
        var blob = ""
        blob.reserveCapacity(min(data.count / 4, 256 * 1024))

        var startIndex = data.startIndex
        while startIndex < data.endIndex {
            let end = data[startIndex...].firstIndex(of: UInt8(ascii: "\n")) ?? data.endIndex
            let lineData = data[startIndex..<end]
            startIndex = end < data.endIndex ? data.index(after: end) : data.endIndex

            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            guard let type = json["type"] as? String, type == "user" || type == "assistant" else { continue }
            let text = extractMessageText(json["message"])
            if text.isEmpty { continue }
            blob.append(text.prefix(500).lowercased())
            blob.append("\n")
        }
        return blob
    }

    /// Message content can be a plain string or an array of content blocks.
    /// Extract plain text from either shape.
    static func extractMessageText(_ message: Any?) -> String {
        guard let msg = message as? [String: Any] else { return "" }
        if let s = msg["content"] as? String { return s }
        guard let blocks = msg["content"] as? [[String: Any]] else { return "" }
        var parts: [String] = []
        for block in blocks {
            if let text = block["text"] as? String { parts.append(text) }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Full conversation load (for preview pane)

    /// Read a JSONL file and parse every user/assistant message in order.
    func loadConversation(filePath: String) -> [ConversationMessage] {
        guard !filePath.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath))
        else { return [] }

        var messages: [ConversationMessage] = []
        var startIndex = data.startIndex
        var index = 0
        let isoFormatter = ISO8601DateFormatter()

        while startIndex < data.endIndex {
            let end = data[startIndex...].firstIndex(of: UInt8(ascii: "\n")) ?? data.endIndex
            let lineData = data[startIndex..<end]
            startIndex = end < data.endIndex ? data.index(after: end) : data.endIndex

            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String else { continue }

            let role: ConversationMessage.Role
            switch type {
            case "user": role = .user
            case "assistant": role = .assistant
            default: continue
            }

            let text = Self.extractMessageText(json["message"])
            // Skip meta/tool-result placeholders that start with "<" (like the current fast parse)
            if text.isEmpty || text.hasPrefix("<") { continue }

            var ts: Date?
            if let s = json["timestamp"] as? String { ts = isoFormatter.date(from: s) }

            messages.append(ConversationMessage(id: index, role: role, text: text, timestamp: ts))
            index += 1
        }
        return messages
    }
}
