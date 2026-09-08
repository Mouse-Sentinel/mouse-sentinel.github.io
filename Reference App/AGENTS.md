# Mouse Sentinel — agent notes

Native macOS SwiftUI app that periodically nudges the mouse cursor (idle keep-alive). Two Swift files; no SPM, tests, CI, or lint scripts.

## Layout

- **Source of truth:** `MouseSentinel/MouseSentinelApp.swift`, `MouseSentinel/ContentView.swift`, `MouseSentinel/Info.plist`
- **Do not use:** `Sources/` (empty leftover). App logic is not an SPM package.
- **Artifacts:** `build/` (CLI bundle), `.build/`, Xcode `DerivedData` — gitignored except as produced locally
- **Xcode:** `MouseSentinel.xcodeproj` scheme `MouseSentinel`
- Bundle id: `com.timgrowney.MouseSentinel` · deployment macOS 14.0 · Swift 6.0

## Commands

```bash
./Scripts/build.sh          # arm64 .app → build/MouseSentinel.app (swiftc + ad-hoc codesign)
open build/MouseSentinel.app
```

Or open the Xcode project and run the `MouseSentinel` scheme. There is no test target.

CLI build is **arm64-only** (`-target arm64-apple-macos14.0`), links AppKit/SwiftUI/CoreGraphics, and must list both `.swift` files in `Scripts/build.sh` if you add sources.

## Architecture (where to edit)

| Concern | Where |
|--------|--------|
| `@main`, menu bar, `AppDelegate` | `MouseSentinelApp.swift` |
| `MouseNudger` (timer, nudge, sleep assertion, activity monitors) | `MouseSentinelApp.swift` — `@MainActor` singleton |
| Window UI, panes, brand chrome | `ContentView.swift` |
| Accessibility / post-event permission UI | `AccessibilityPermissionMonitor` in `ContentView.swift` |

Cursor move path: `CGDisplayMoveCursorToPoint` → fallback `CGWarpMouseCursorPosition`, plus `CGEvent` mouse-moved post. Self-nudges are ignored briefly (`ignoreMouseActivityUntil`) so monitors do not reset the countdown.

Nudge interval is **5…60s** (default **15**), not a hard-coded 5s. When enabled, app also holds idle sleep via `ProcessInfo.beginActivity`.

## Gotchas

- Moving the cursor needs **Accessibility** and/or **post-event** access; UI opens System Settings privacy. Global `NSEvent` monitors require trust.
- Coordinate space: AppKit `NSEvent.mouseLocation` is bottom-left origin; CoreGraphics display points are top-left — conversion lives in `moveCursor(to:)`.
- Window is fixed **560×760**; keep layout changes inside that unless you change both `defaultSize` and `ContentView` frame.
- `Info.plist` is copied as-is by `build.sh` (`GENERATE_INFOPLIST_FILE = NO` in Xcode). Bump version there.
- README still says “every 5 seconds”; code uses a configurable interval — prefer code over README if they disagree.
