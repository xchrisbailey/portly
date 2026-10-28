#!/usr/bin/env bash
# PROTOTYPE (wayfinder #13): plain hdiutil + Finder AppleScript. Throwaway.
#   make-dmg.sh <path/to/Portly.app> <version> [outdir]
set -euo pipefail
APP="$1"; VERSION="$2"; OUT="${3:-.}"
HERE="$(cd "$(dirname "$0")" && pwd)"
VOL="Portly"; NAME="Portly-$VERSION"
W=660; H=400
STAGE="$(mktemp -d)"; RW="$(mktemp -d)/rw.dmg"

python3 - "$STAGE" <<'PY'
import sys, os
from PIL import Image, ImageDraw, ImageFont
d = os.path.join(sys.argv[1], ".background"); os.makedirs(d)
W, H = 660, 400
img = Image.new("RGB", (W, H))
px = img.load()
for y in range(H):
    for x in range(W):
        t = y / H
        px[x, y] = (int(246 - 22*t), int(247 - 20*t), int(250 - 14*t))
dr = ImageDraw.Draw(img)
try: f = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 20)
except Exception: f = ImageFont.load_default()
msg = "Drag Portly to Applications"
tw = dr.textlength(msg, font=f)
dr.text(((W - tw) / 2, 40), msg, fill=(70, 74, 84), font=f)
# arrow between the two icon slots (app at x=170, Applications at x=490, y=200)
dr.line([(255, 205), (395, 205)], fill=(150, 156, 168), width=5)
dr.polygon([(395, 188), (425, 205), (395, 222)], fill=(150, 156, 168))
img.save(os.path.join(d, "bg.png"))
PY

cp -R "$APP" "$STAGE/Portly.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1}')"
sleep 2
osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 200 + $W, 120 + $H}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set background picture of opts to file ".background:bg.png"
    set position of item "Portly.app" of container window to {170, 200}
    set position of item "Applications" of container window to {490, 200}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
sync
hdiutil detach "$DEV" >/dev/null
mkdir -p "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT/$NAME.dmg" >/dev/null
rm -rf "$STAGE" "$(dirname "$RW")"
echo "Built $OUT/$NAME.dmg"
