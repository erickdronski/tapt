#!/bin/bash
# Render the Tapt IG assets to PNG at 2x. Requires Google Chrome.
DIR="$(cd "$(dirname "$0")" && pwd)"; OUT="$DIR/out"; mkdir -p "$OUT"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
r(){ "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --virtual-time-budget=4000 --window-size=$2,$3 --screenshot="$OUT/${1%.html}.png" "file://$DIR/$1" >/dev/null 2>&1; }
r avatar.html 1080 1080
r post-01-meet.html 1080 1350
r post-03-taste-guinness.html 1080 1350
echo "done"
