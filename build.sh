#!/bin/bash
# Builds "Quest Log.app" and the `quest` command into build/.
#   ./build.sh            build only
#   ./build.sh install    also copy the app to ~/Applications and `quest` to ~/.local/bin
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --product QuestLog
swift build -c release --product quest
bin="$(swift build -c release --show-bin-path)"

app="build/Quest Log.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Fonts"
cp "$bin/QuestLog" "$app/Contents/MacOS/QuestLog"
cp "$bin/quest" build/quest
cp Resources/Fonts/* "$app/Contents/Resources/Fonts/"
version="$(git describe --tags --always 2>/dev/null || echo 0.1.0)"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Quest Log</string>
  <key>CFBundleDisplayName</key><string>Quest Log</string>
  <key>CFBundleIdentifier</key><string>com.davafons.questlog</string>
  <key>CFBundleExecutable</key><string>QuestLog</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key>
  <array><dict><key>CFBundleURLName</key><string>Quest Log</string><key>CFBundleURLSchemes</key><array><string>questlog</string></array></dict></array>
</dict>
</plist>
PLIST
codesign --force --sign - "$app" >/dev/null
echo "Built $app and build/quest"

if [ "${1:-}" = install ]; then
  mkdir -p ~/Applications ~/.local/bin
  pkill -x QuestLog 2>/dev/null || true
  rm -rf ~/Applications/"Quest Log.app"
  cp -R "$app" ~/Applications/
  install -m 755 build/quest ~/.local/bin/quest
  open ~/Applications/"Quest Log.app"
  echo "Installed ~/Applications/Quest Log.app and ~/.local/bin/quest"
fi
