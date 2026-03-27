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

    /// Fast parse: only reads the first 15 lines (enough for metadata + first message).
    /// Uses file modification date for lastMessageAt — avoids scanning thousands of lines.
    private func parsePastSession(from file: URL, projectDir: String) -> PastSession? {
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast

        // Read only the head of the file — enough for metadata + first message
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        var buffer = Data()
        // Read up to ~8KB — more than enough for 15 JSONL lines
        for _ in 0..<16 {
            let chunk = handle.readData(ofLength: 512)
            if chunk.isEmpty { break }
            buffer.append(chunk)
        }

        return Self.parsePastSessionData(buffer, fileModificationDate: mtime, projectDir: projectDir)
    }
}
