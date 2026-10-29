#!/usr/bin/env bash
# Assembles Portly.app from the SwiftPM release build.
#   scripts/build-app.sh                 0.0.0-dev build into ./build/Portly.app, installed into /Applications
#   scripts/build-app.sh --build-only    same, don't install
#   scripts/build-app.sh --version 1.2.3 [--build-number N] [--build-only]
#                                        release build: universal (arm64 + x86_64), version and build
#                                        number written to Info.plist; build number defaults to the
#                                        commit count on main
#                                        release builds are signed with the Developer ID Application
#                                        identity (hardened runtime, secure timestamp, no entitlements);
#                                        dev builds are signed ad hoc and need no certificate
#   BUILD_DIR=/some/dir scripts/build-app.sh
#   PORTLY_SIGN_IDENTITY="Developer ID Application: ..." overrides the keychain lookup (name or SHA-1)
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=scripts/sign-identity.sh
source scripts/sign-identity.sh
BUILD_DIR="${BUILD_DIR:-build}"
APP="$BUILD_DIR/Portly.app"

VERSION=""
BUILD_NUMBER=""
INSTALL=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
        --build-number) BUILD_NUMBER="${2:?--build-number needs a value}"; shift 2 ;;
        --build-only) INSTALL=0; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# The version and build number go into an unquoted heredoc below, so keep them to safe characters.
if [[ -n "$VERSION" && ! "$VERSION" =~ ^[0-9A-Za-z.+-]+$ ]]; then
    echo "error: --version must use only letters, digits, '.', '+' and '-', got '$VERSION'" >&2
    exit 2
fi
if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "error: --build-number must be a number, got '$BUILD_NUMBER'" >&2
    exit 2
fi

# A version means a release: universal binary. No version is the local dev build.
ARCH_FLAGS=()
RELEASE=0
IDENTITY=""
if [[ -n "$VERSION" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
    RELEASE=1
    # Fail before the slow build if there is nothing to sign with.
    require_sign_identity || exit 1
    IDENTITY="$SIGN_IDENTITY"
else
    VERSION="0.0.0-dev"
fi
if [[ -z "$BUILD_NUMBER" ]]; then
    if [[ "$RELEASE" == 1 ]]; then
        # A release must not ship a made-up build number.
        BUILD_NUMBER="$(git rev-list --count main)" \
            || { echo "error: could not count commits on main for the build number; pass --build-number" >&2; exit 1; }
    else
        BUILD_NUMBER="$(git rev-list --count main 2>/dev/null || echo 1)"
    fi
fi

swift build -c release --product Portly ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
# A universal build lands under .build/apple/Products/Release, so ask SwiftPM with the same flags.
BIN_DIR="$(swift build -c release --product Portly ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Portly" "$APP/Contents/MacOS/Portly"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R "$BIN_DIR/Portly_Portly.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>computer.srcery.portly</string>
    <key>CFBundleName</key><string>Portly</string>
    <key>CFBundleDisplayName</key><string>Portly</string>
    <key>CFBundleExecutable</key><string>Portly</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [[ "$RELEASE" == 1 ]]; then
    # Sign inside out: the app's seal covers the files in Contents/Resources, so the nested SwiftPM
    # resource bundle must be signed before the app, or signing it afterwards would break the seal.
    # No --deep (it is deprecated for signing) and no entitlements: Portly needs none.
    SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
    "${SIGN[@]}" "$APP/Contents/Resources/Portly_Portly.bundle"
    "${SIGN[@]}" "$APP"
    codesign -vvv --deep --strict "$APP"
else
    # Apple silicon refuses to run unsigned binaries, so sign ad hoc (no identity needed).
    codesign --force --sign - "$APP"
fi
echo "Built $APP"

if [[ "$INSTALL" == 1 ]]; then
    rm -rf /Applications/Portly.app
    cp -R "$APP" /Applications/Portly.app
    echo "Installed /Applications/Portly.app"
fi
