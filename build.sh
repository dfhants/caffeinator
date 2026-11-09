#!/bin/bash
# Builds Caffeinator.app and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Caffeinator.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 -target arm64-apple-macos13 main.swift -o "$APP/Contents/MacOS/Caffeinator-arm64"
swiftc -O -swift-version 5 -target x86_64-apple-macos13 main.swift -o "$APP/Contents/MacOS/Caffeinator-x86_64"
lipo -create "$APP/Contents/MacOS/Caffeinator-arm64" "$APP/Contents/MacOS/Caffeinator-x86_64" -output "$APP/Contents/MacOS/Caffeinator"
rm "$APP/Contents/MacOS/Caffeinator-arm64" "$APP/Contents/MacOS/Caffeinator-x86_64"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Caffeinator</string>
    <key>CFBundleIdentifier</key><string>local.caffeinator</string>
    <key>CFBundleName</key><string>Caffeinator</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

if [[ "${1:-}" != "--no-install" ]]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/Caffeinator.app
    cp -R "$APP" ~/Applications/
    echo "Installed to ~/Applications/Caffeinator.app"
fi
