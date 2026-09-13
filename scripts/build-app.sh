#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/build/Maw Chat.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
scripts/build-icon.sh "$APP/Contents/Resources/MawChatIcon.icns"
cp "$(swift build -c release --show-bin-path)/MawChat" "$APP/Contents/MacOS/MawChat"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MawChat</string>
<key>CFBundleIdentifier</key><string>studio.soulbrews.mawchat</string>
<key>CFBundleName</key><string>Maw Chat</string>
<key>CFBundleIconFile</key><string>MawChatIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
