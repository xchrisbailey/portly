#!/usr/bin/env bash
# Builds a signed, drag-to-install Portly-X.Y.Z.dmg from an already signed Portly.app.
#   scripts/make-dmg.sh <path/to/Portly.app> <version> <output dir>
#   needs `brew install create-dmg`; it drives Finder via AppleScript, so run it in a GUI session
#   that has granted Automation permission. The DMG is signed with the Developer ID Application
#   identity (secure timestamp), found the same way as in build-app.sh.
#   PORTLY_SIGN_IDENTITY="Developer ID Application: ..." overrides the keychain lookup (name or SHA-1)
#   PORTLY_DMG_TIMEOUT  seconds to let create-dmg run before it is stopped (default: 600)
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=scripts/sign-identity.sh
source scripts/sign-identity.sh

if [[ $# -ne 3 ]]; then
    echo "usage: scripts/make-dmg.sh <path/to/Portly.app> <version> <output dir>" >&2
    exit 2
fi
APP="$1"
VERSION="$2"
OUT_DIR="$3"
DMG="$OUT_DIR/Portly-$VERSION.dmg"

if ! command -v create-dmg >/dev/null; then
    echo "error: create-dmg is not installed; run: brew install create-dmg" >&2
    exit 1
fi
if [[ ! -d "$APP" ]]; then
    echo "error: app not found: $APP" >&2
    exit 1
fi
# Fail before the slow DMG build if there is nothing to sign with.
require_sign_identity || exit 1
IDENTITY="$SIGN_IDENTITY"

mkdir -p "$OUT_DIR"
# create-dmg refuses to overwrite an existing DMG.
rm -f "$DMG"

# Layout (approved in #13): 660x400 window, icon size 128, app left, Applications link right.
# create-dmg takes the app's directory as its source folder; stage the app alone so nothing else lands in the DMG.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Portly.app"

# create-dmg drives Finder and can stall (Automation permission prompt, a mounted Portly volume),
# so run it under a watchdog. The watchdog's output is redirected so a surviving sleep can't hold
# a pipe open after the script exits.
create-dmg \
    --volname Portly \
    --background assets/dmg-background.png \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon Portly.app 170 200 \
    --app-drop-link 490 200 \
    --hide-extension Portly.app \
    --no-internet-enable \
    "$DMG" "$STAGE" &
dmg_pid=$!
TIMEOUT="${PORTLY_DMG_TIMEOUT:-600}"
( sleep "$TIMEOUT"; kill "$dmg_pid" 2>/dev/null ) >/dev/null 2>&1 &
watchdog=$!
dmg_rc=0
wait "$dmg_pid" || dmg_rc=$?
{ kill "$watchdog" && wait "$watchdog"; } 2>/dev/null || true
if [[ "$dmg_rc" -eq 143 ]]; then
    echo "error: create-dmg did not finish within ${TIMEOUT}s and was stopped; check Finder Automation permission and eject any mounted Portly volume" >&2
    exit 1
elif [[ "$dmg_rc" -ne 0 ]]; then
    exit "$dmg_rc"
fi

codesign --force --timestamp --sign "$IDENTITY" "$DMG"
codesign -vvv "$DMG"
echo "Built $DMG"
