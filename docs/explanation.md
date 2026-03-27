# How Clam Works

## Architecture

Clam is a native macOS menu bar app built with Swift and SwiftUI. It has no external dependencies.

```
AppDelegate (entry point)
    ↓
SessionState (@Published) ← SessionMonitor (polls sessions)
                           ← UsageMonitor  (polls usage + OAuth)
    ↓
Views (menu bar, popover, search panel, settings)
```

**AppDelegate** owns the status item, popover, and polling loops. It wires everything together.

**SessionState** is the single observable model. All views react to its `@Published` properties — no manual refresh needed.

## Data sources

### Active sessions

Clam reads `~/.claude/sessions/*.json`. Each file is named `{pid}.json` and contains `sessionId`, `cwd`, `startedAt`, and optional `name`. Clam verifies the PID is still alive via `kill(pid, 0)` — no subprocess spawning.

Polled every **5 seconds**.

### Past sessions

Clam scans `~/.claude/projects/{projectId}/*.jsonl` files. It reads only the first 15 lines of each file to extract `sessionId`, `cwd`, and the first user message. File modification time is used as `lastMessageAt` to avoid scanning entire files.

Results are cached for 30 seconds and pre-warmed on app launch.

### Rate limits

Read from `~/.claude/usage-cache.json` which Claude Code maintains. Contains `five_hour`, `seven_day`, and `seven_day_sonnet` rate windows with utilization (0–100) and reset time.

Polled every **60 seconds**. Clam also triggers an OAuth refresh in the background to keep this file up to date.

### Token usage

Clam calls the `ccusage` CLI in the background to get daily and monthly token counts and costs. Results are cached in `~/.cache/clam/` with a 5-minute TTL.

## Terminal detection

When listing active sessions, Clam walks the process tree upward from each `claude` PID using `sysctl` (no subprocess). It skips shells and system processes, then resolves the first GUI app it finds. Electron apps (VS Code, Cursor, etc.) are resolved from their helper processes to the main bundle.

## Session resume

Resuming a past session requires two things:
1. **Working directory** — `claude --resume` is directory-scoped, so Clam `cd`s into the session's `cwd` first
2. **Absolute path** — GUI apps have a minimal `PATH`, so Clam resolves the full path to `claude`

For CLI terminals (Ghostty, Alacritty, WezTerm), the command runs inside a login shell (`zsh -l -c`) to load the user's environment, with `exec $SHELL` as a fallback if claude exits.

For AppleScript terminals (Terminal.app, iTerm2), the command runs via `do script` which inherits the user's shell profile.

## Security

- **No dependencies** — immune to supply chain attacks
- **UUID validation** — session IDs are validated before use in commands
- **Shell escaping** — all paths are single-quote escaped before interpolation
- **Array-based args** — CLI terminals use `Process` with argument arrays, not shell strings
- **Keychain** — OAuth tokens are read from macOS Keychain, never stored in plaintext
- **Atomic writes** — cache files use write-to-tmp + rename to avoid race conditions
