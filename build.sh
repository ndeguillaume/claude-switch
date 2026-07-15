#!/bin/bash
# Compile le binaire release et assemble dist/ClaudeSwitch.app (bundle menu bar, signé ad hoc).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

[ -f Resources/AppIcon.icns ] || swift Scripts/generate_icon.swift

APP="dist/Claude Switch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/ClaudeSwitch "$APP/Contents/MacOS/ClaudeSwitch"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for bundle in .build/release/*.bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ndeguillaume.claudeswitch</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>fr</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>fr</string>
        <string>en</string>
    </array>
    <key>CFBundleName</key>
    <string>Claude Switch</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Switch</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeSwitch</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - "$APP"

echo "OK : $APP"
