#!/usr/bin/env bash
# Builds StudySprint.app (a normal double-clickable Mac app) into ./build/
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/StudySprint"

APP="build/StudySprint.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/StudySprint"

# App icon (rendered from code, so no binary assets in the repo).
ICONSET="$(mktemp -d)/AppIcon.iconset"
if swift Scripts/make-icon.swift "$ICONSET" >/dev/null 2>&1 && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"; then
  echo "Icon generated"
else
  echo "Icon generation skipped"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>StudySprint</string>
  <key>CFBundleDisplayName</key><string>StudySprint</string>
  <key>CFBundleIdentifier</key><string>com.studysprint.app</string>
  <key>CFBundleExecutable</key><string>StudySprint</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS will launch it locally.
codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"
echo "Run it with:  open $APP   (or drag it into /Applications)"
