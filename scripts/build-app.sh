#!/usr/bin/env bash
# Assembles Portly.app from the SwiftPM release build.
#   scripts/build-app.sh                 build into ./build/Portly.app
#   scripts/build-app.sh --install       also copy it into /Applications
#   BUILD_DIR=/some/dir scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR="${BUILD_DIR:-build}"
APP="$BUILD_DIR/Portly.app"

swift build -c release --product Portly
BIN="$(swift build -c release --product Portly --show-bin-path)/Portly"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Portly"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>computer.srcery.portly</string>
    <key>CFBundleName</key><string>Portly</string>
    <key>CFBundleDisplayName</key><string>Portly</string>
    <key>CFBundleExecutable</key><string>Portly</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so the unsigned personal build launches on Apple silicon.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/Portly.app
    cp -R "$APP" /Applications/Portly.app
    echo "Installed /Applications/Portly.app"
fi
