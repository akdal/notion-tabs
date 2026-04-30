#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${0}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/artifacts/Notion Tabs.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$ROOT_DIR/artifacts/Notion Tabs UI.app" "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swift build -c release

cp "$BUILD_DIR/notion-tabs-ui" "$MACOS_DIR/notion-tabs-ui"
cp "$BUILD_DIR/notion-tabs" "$MACOS_DIR/notion-tabs"

swift "$ROOT_DIR/scripts/generate-app-icon.swift" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>notion-tabs-ui</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.huey.notiontabs.ui</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Notion Tabs</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/notion-tabs-ui" "$MACOS_DIR/notion-tabs"
codesign --force --deep --sign - "$APP_DIR" >/dev/null
printf '%s\n' "$APP_DIR"
