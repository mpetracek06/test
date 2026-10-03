#!/usr/bin/env bash
# Launches the built app in each screen with demo data and captures the window.
# Usage: Scripts/screenshots.sh <output-dir>
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-../docs/screenshots}"
mkdir -p "$OUT"
BIN="build/StudySprint.app/Contents/MacOS/StudySprint"
swiftc -O Scripts/window-id.swift -o /tmp/window-id 2>/dev/null

for screen in new setup research plan sprint testout recall map tutor quiz quizq feynman cards review; do
  STUDYSPRINT_SCREEN="$screen" "$BIN" >/dev/null 2>&1 &
  pid=$!
  sleep 7
  wid=$(/tmp/window-id "$pid" || true)
  if [ -n "$wid" ]; then
    screencapture -x -o -l "$wid" "/tmp/$screen.png"
  else
    echo "no window for $screen; capturing full screen"
    screencapture -x "/tmp/$screen.png"
  fi
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  if [ -f "/tmp/$screen.png" ]; then
    sips -Z 1600 "/tmp/$screen.png" --out "$OUT/$screen.png" >/dev/null && echo "captured $screen"
  fi
done
