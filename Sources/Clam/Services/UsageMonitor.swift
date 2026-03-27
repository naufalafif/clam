import Foundation

// MARK: - Reads Claude rate limits from ~/.claude/usage-cache.json
// Mirrors claude-bar exactly: read existing cache immediately, refresh via OAuth in background

actor UsageMonitor {
    private let cacheFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/usage-cache.json")
    // SECURITY: use per-user temp dir instead of world-readable /tmp
    private let tokenCacheDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/clam")

    private var lastOAuthRefresh: Date?
    private let oauthTTL: TimeInterval = 60

    // MARK: - Public

    func fetchUsage() async -> UsageData {
        // Always read existing cache first (fast, no network)
        let limits = readRateLimits()
        let tokens = readTokenUsage()

        // Trigger OAuth refresh in background if cache is stale
        refreshOAuthIfNeeded()

        return UsageData(
            fiveHour: limits.fiveHour,
            sevenDay: limits.sevenDay,
            sevenDaySonnet: limits.sevenDaySonnet,
            dailyTokens: tokens.daily,
            monthlyTokens: tokens.monthly
        )
    }

    // MARK: - OAuth cache refresh (fire-and-forget, mirrors claude-bar)

    private func refreshOAuthIfNeeded() {
        // Check file mtime — only refresh if >60s old
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
           let mtime = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(mtime) < oauthTTL {
            return
        }

        Task.detached(priority: .background) {
            await self.performOAuthRefresh()
        }
    }

    private func performOAuthRefresh() async {
        guard let token = readOAuthToken() else { return }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return }

        let tmp = cacheFile.deletingLastPathComponent().appendingPathComponent("usage-cache.json.tmp")
        try? data.write(to: tmp)
        // SECURITY: atomic replace — moveItem fails if dest exists
        _ = try? FileManager.default.replaceItemAt(cacheFile, withItemAt: tmp)
    }

    /// Gets OAuth token from macOS Keychain — same as claude-bar's `security` call
    private func readOAuthToken() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-a", NSUserName(), "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }

        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { return nil }
        return token
    }

    // MARK: - Rate limit parsing (reads ~/.claude/usage-cache.json)

    struct RateLimits {
        let fiveHour: RateLimit
        let sevenDay: RateLimit
        let sevenDaySonnet: RateLimit?
    }

    // MARK: - Parsing helpers (internal for testing)

    static func parseRateLimitJSON(_ json: [String: Any]) -> RateLimits {
        func parseLimit(_ key: String) -> RateLimit? {
            guard let block = json[key] as? [String: Any] else { return nil }
            let utilization = ((block["utilization"] as? Double) ?? 0) / 100.0
            var resetsAt: Date?
            if let iso = block["resets_at"] as? String {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                resetsAt = fmt.date(from: iso)
            }
            return RateLimit(utilization: utilization, resetsAt: resetsAt)
        }

        return RateLimits(
            fiveHour: parseLimit("five_hour") ?? .empty,
            sevenDay: parseLimit("seven_day") ?? .empty,
            sevenDaySonnet: parseLimit("seven_day_sonnet")
        )
    }

    static func parseTokenJSON(_ json: [String: Any]) -> TokenUsage? {
        guard let totals = json["totals"] as? [String: Any],
              let tokens = totals["totalTokens"] as? Int,
              let cost   = totals["totalCost"] as? Double
        else { return nil }
        return TokenUsage(tokens: tokens, cost: cost)
    }

    private func readRateLimits() -> RateLimits {
        guard let data = try? Data(contentsOf: cacheFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return RateLimits(fiveHour: .empty, sevenDay: .empty, sevenDaySonnet: nil) }

        let parsed = Self.parseRateLimitJSON(json)
        return RateLimits(
            fiveHour: parsed.fiveHour,
            sevenDay: parsed.sevenDay,
            sevenDaySonnet: parsed.sevenDaySonnet
        )
    }

    // MARK: - Token usage via ccusage (mirrors claude-bar)

    private func readTokenUsage() -> (daily: TokenUsage?, monthly: TokenUsage?) {
        try? FileManager.default.createDirectory(at: tokenCacheDir, withIntermediateDirectories: true)

        let dailyFile  = tokenCacheDir.appendingPathComponent("daily.json")
        let monthlyFile = tokenCacheDir.appendingPathComponent("monthly.json")

        // Refresh if stale (>5 min), fire-and-forget
        if shouldRefreshTokenCache(file: dailyFile) {
            Task.detached(priority: .background) { self.refreshTokenCache() }
        }

        return (parseTokenFile(dailyFile), parseTokenFile(monthlyFile))
    }

    private func shouldRefreshTokenCache(file: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let mtime = attrs[.modificationDate] as? Date
        else { return true }
        return Date().timeIntervalSince(mtime) > 300
    }

    nonisolated private func refreshTokenCache() {
        let ccusagePaths = ["/opt/homebrew/bin/ccusage", "/usr/local/bin/ccusage", "/usr/bin/ccusage"]
        guard let ccusage = ccusagePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return }

        let today      = Self.dateString(offsetDays: 0)
        let monthStart = Self.monthStartString()

        let runs: [(args: [String], file: String)] = [
            (["daily", "--since", today, "--json", "--offline", "--no-color"],
             "\(FileManager.default.homeDirectoryForCurrentUser.path)/.cache/clam/daily.json"),
            (["monthly", "--since", monthStart, "--json", "--offline", "--no-color"],
             "\(FileManager.default.homeDirectoryForCurrentUser.path)/.cache/clam/monthly.json")
        ]

        for run in runs {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: ccusage)
            task.arguments = run.args
            // Provide homebrew PATH so ccusage can find node
            task.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError  = Pipe()
            guard (try? task.run()) != nil else { continue }
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if task.terminationStatus == 0, !data.isEmpty {
                try? data.write(to: URL(fileURLWithPath: run.file))
            }
        }
    }

    private func findCCUsage() -> String? {
        ["/opt/homebrew/bin/ccusage", "/usr/local/bin/ccusage", "/usr/bin/ccusage"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func parseTokenFile(_ file: URL) -> TokenUsage? {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return Self.parseTokenJSON(json)
    }

    private static func dateString(offsetDays: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offsetDays, to: Date()) ?? Date()
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f.string(from: date)
    }

    private static func monthStartString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMM01"; return f.string(from: Date())
    }
}
