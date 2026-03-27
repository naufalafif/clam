# Contributing

## Setup

```sh
git clone https://github.com/naufalafif/clam.git
cd clam
make run
```

Requires macOS 13+ and Swift 5.9+ (included with Xcode Command Line Tools).

## Development workflow

```sh
make run          # build + launch (kills existing instance)
make test         # run test suite
make check        # build + test + lint + format check
```

## Before submitting a PR

1. Run `make check` — all checks must pass
2. Follow [conventional commits](https://www.conventionalcommits.org/) for PR titles:
   `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, `ci:`, `security:`
3. No external dependencies — Clam is zero-dependency by design

## Project structure

```
Sources/Clam/
  Models/        — Data types (Session, UsageData)
  Services/      — Business logic (SessionMonitor, UsageMonitor, TerminalLauncher, etc.)
  Views/         — SwiftUI views (MenuBarView, MenuContentView, etc.)
  main.swift     — Entry point
  AppDelegate.swift — App lifecycle, popover, polling
Tests/           — Standalone test scripts (no Xcode required)
scripts/         — Build and release helpers
```
