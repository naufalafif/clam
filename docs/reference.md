# Reference

## Settings

| Setting | Options | Default |
|---------|---------|---------|
| Preferred terminal | Automatic, Ghostty, iTerm2, Terminal, Alacritty, WezTerm | Automatic |
| Launch at login | On / Off | Off |

**Automatic** terminal selection picks the first installed terminal in this order: Ghostty → iTerm2 → Alacritty → WezTerm → Terminal.

Settings are stored in `UserDefaults` under the key `preferredTerminal`.

## Data paths

| Path | Purpose |
|------|---------|
| `~/.claude/sessions/*.json` | Active session metadata (one per running claude process) |
| `~/.claude/projects/{id}/*.jsonl` | Past session conversation logs |
| `~/.claude/usage-cache.json` | Rate limit data maintained by Claude Code |
| `~/.cache/clam/daily.json` | Cached daily token usage from ccusage |
| `~/.cache/clam/monthly.json` | Cached monthly token usage from ccusage |

## Poll intervals

| Data | Interval |
|------|----------|
| Active sessions | 5 seconds |
| Rate limits | 60 seconds |
| Token usage (ccusage) | 5 minutes (cache TTL) |
| OAuth refresh | 60 seconds |
| Past session cache | 30 seconds |

## Supported terminals

| Terminal | Launch method | Notes |
|----------|--------------|-------|
| Ghostty | CLI (`-e`) | Launched via app bundle binary or `/opt/homebrew/bin` |
| iTerm2 | AppleScript | Uses `create window with default profile command` |
| Terminal.app | AppleScript | Uses `do script` |
| Alacritty | CLI (`-e`) | Launched via app bundle binary or `/opt/homebrew/bin` |
| WezTerm | CLI (`start --`) | Supports `--cwd` for working directory |

All CLI terminals wrap the command in a login shell (`/bin/zsh -l -c`) to ensure the user's environment is loaded.

## App configuration

| Key | Value |
|-----|-------|
| Bundle ID | `com.naufal.clam` |
| Minimum macOS | 13.0 (Ventura) |
| LSUIElement | `true` (menu bar only, no dock icon) |

## Makefile targets

| Target | Description |
|--------|-------------|
| `make build` | Debug build |
| `make run` | Build, bundle, and launch |
| `make release` | Optimized release build |
| `make install` | Release build → `/Applications` |
| `make uninstall` | Remove from `/Applications` |
| `make dist` | Release build → `dist/Clam.zip` |
| `make test` | Run test suite |
| `make lint` | SwiftLint (strict) |
| `make format` | Auto-format with swift-format |
| `make check` | Build + test + lint + format check |
| `make icon` | Regenerate `AppIcon.icns` |
| `make clean` | Remove build artifacts |
