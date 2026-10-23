#!/bin/zsh
# Compila MiNavegador y lo empaqueta como build/MiNavegador.app
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MiNavegador"

APP="build/MiNavegador.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MiNavegador"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MiNavegador</string>
    <key>CFBundleDisplayName</key><string>MiNavegador</string>
    <key>CFBundleIdentifier</key><string>com.carlosvp.minavegador</string>
    <key>CFBundleExecutable</key><string>MiNavegador</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Listo: $APP"
