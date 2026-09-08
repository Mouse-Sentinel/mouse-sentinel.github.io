#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
MODULE_CACHE_DIR="/private/tmp/mouse-sentinel-modulecache"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
APP_NAME="MouseSentinel"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"
EXECUTABLE_PATH="$BUNDLE_DIR/Contents/MacOS/$APP_NAME"
PLIST_PATH="$BUNDLE_DIR/Contents/Info.plist"
ICNS_PATH="$BUNDLE_DIR/Contents/Resources/$APP_NAME.icns"

mkdir -p "$BUILD_DIR" "$MODULE_CACHE_DIR" "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"

xcrun swiftc \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -target arm64-apple-macos14.0 \
  -sdk "$SDK_PATH" \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreGraphics \
  "$ROOT_DIR/MouseSentinel/MouseSentinelApp.swift" \
  "$ROOT_DIR/MouseSentinel/ContentView.swift" \
  "$ROOT_DIR/MouseSentinel/Icons.swift" \
  -o "$EXECUTABLE_PATH"

# Render the bundle .icns from the same shape code the app uses at runtime.
xcrun swiftc \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -target arm64-apple-macos14.0 \
  -sdk "$SDK_PATH" \
  -framework AppKit \
  -framework SwiftUI \
  -framework CoreGraphics \
  "$ROOT_DIR/Scripts/render_icon.swift" \
  "$ROOT_DIR/MouseSentinel/Icons.swift" \
  -o "$BUILD_DIR/render-icon-bin"

"$BUILD_DIR/render-icon-bin" "$ICNS_PATH"

cp "$ROOT_DIR/MouseSentinel/Info.plist" "$PLIST_PATH"

codesign --force --deep --sign - "$BUNDLE_DIR"

# Re-register with LaunchServices so the Dock uses the freshly built .icns
# instead of a stale cached/generic icon (and never flashes the default one
# when the app quits).
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$BUNDLE_DIR"