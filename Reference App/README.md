# Mouse Sentinel

A tiny native macOS utility that shows a single on/off toggle. When enabled, it nudges the mouse cursor a small random distance in a random direction every 5 seconds.

## Run

Open `MouseSentinel.xcodeproj` in Xcode and run the `MouseSentinel` scheme, or use the repeatable command-line build:

```bash
./Scripts/build.sh
```

## Notes

- The app uses `CGWarpMouseCursorPosition` to move the cursor.
- If macOS prompts for accessibility or input control permission, allow it so the cursor movement can work.
- The command-line build emits an arm64 `.app` bundle at `build/MouseSentinel.app`.
