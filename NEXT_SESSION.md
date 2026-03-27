# Next Session Prompt

Copy everything below the line and paste as your first message in the new session.

---

## Context

I'm working on **Clam**, a macOS menu bar app (Swift/SwiftUI) at `/Users/naufal/Workspace/personal/claude-manager/`. It monitors Claude Code sessions and API usage. The backend is solid and shipped — session resume, terminal launching, tests, CI, docs all work.

The repo is at `github.com/naufalafif/clam` — CI is green.

## Current State

The app is on the **last committed working state** (`git log --oneline -1` to see). Everything was reverted to the last good commit after failed UI attempts.

## Open UI Issues (3 things to fix)

### 1. Menu bar icon not showing
- The menu bar only shows text like "0% " — no shell icon visible
- The app uses a SwiftUI `ClickThroughHostingView` subview on the `NSStatusBarButton` with `Image(systemName: "fossil.shell.fill")` in `MenuBarView.swift`
- The SF Symbol exists (verified programmatically) but doesn't render visually in the menu bar
- A standalone test app using native `button.image` with the same SF Symbol works perfectly
- Root cause likely: the SwiftUI hosting subview approach doesn't properly render SF Symbols as template images in the menu bar
- **Fix direction**: Replace the SwiftUI subview approach with native `button.image` (template) + `button.title` on `NSStatusBarButton`

### 2. Menu bar click requires hold to open
- Clicking the menu bar icon requires holding — a quick single click doesn't toggle the popover
- The app uses `popover.behavior = .transient` with `button.action = #selector(togglePopover)`
- Reference tutorials (e.g. anaghsharma.com/blog/macos-menu-bar-app-with-swiftui) show the same pattern working with single click
- Might be related to the `ClickThroughHostingView` intercepting mouse events (its `hitTest` returns nil, but the subview still sits on top of the button)
- **Fix direction**: Remove SwiftUI subview from button (same fix as #1), use `EventMonitor` for outside-click dismissal with `.applicationDefined` behavior

### 3. Sessions section should be responsive
- Currently the popover is fixed 300×420 with `ScrollView` taking all remaining space
- Want: sessions section height follows number of sessions, only becomes scrollable after 3+ active sessions
- With 0-2 sessions, the popover should be more compact (less empty space)
- Previous attempts to change `frame(height:)` or use dynamic `contentSize` caused layout to break (content centered with padding, or popover positioned wrong)
- **Fix direction**: Need to actually see the UI to get this right — use `screencapture` after each change

## How to Verify Changes

**IMPORTANT**: Before this session, I granted Screen Recording permission to Terminal. Use `screencapture` to capture the menu bar and popover after each change:

```bash
# Capture full screen
screencapture -x /tmp/screen.png

# Capture specific region (menu bar area)
screencapture -x -R 0,0,800,30 /tmp/menubar.png
```

Then read the screenshot with the `Read` tool to see what's actually rendering. This prevents the blind guessing loop we were stuck in.

## Key Files

- `Sources/Clam/AppDelegate.swift` — status item setup, popover toggle, polling
- `Sources/Clam/Views/MenuBarView.swift` — SwiftUI menu bar view (icon + text)
- `Sources/Clam/Views/MenuContentView.swift` — main popover layout (300×420)
- `Sources/Clam/Views/SessionRowView.swift` — active session row
- `Sources/Clam/Services/EventMonitor.swift` — global click monitor (exists but not wired up)

## Build & Run

```bash
make run    # build + bundle + launch
swift build # just compile
make test   # run tests
```

## What NOT to Do

- Don't guess at UI fixes without screencapturing the result
- Don't change multiple things at once — one fix at a time, verify with screenshot
- Don't change popover contentSize dynamically (caused position bugs)
- Don't use `sendAction(on: .leftMouseDown)` (was tried, didn't help)

## Approach

Fix issues one at a time in this order:
1. Fix icon + click (both solved by replacing SwiftUI subview with native button properties)
2. Fix responsive sessions (needs visual verification)

After each change: build → launch → screencapture → read screenshot → verify → next fix.
