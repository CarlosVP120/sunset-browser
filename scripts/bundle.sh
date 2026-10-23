#!/bin/zsh
# Compila Sunset Browser y lo empaqueta como "build/Sunset Browser.app"
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MiNavegador"

APP="build/Sunset Browser.app"
rm -rf "$APP" build/MiNavegador.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sunset Browser"

# Icono hecho con Icon Composer (Resources/AppIcon.icon): actool genera el Assets.car con el
# icono de Liquid Glass (claro/oscuro/tintado) y un .icns para versiones anteriores de macOS.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist "$(mktemp -d)/partial.plist" >/dev/null

# El identificador sigue siendo el de siempre: con él macOS guarda las cookies y sesiones.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Sunset Browser</string>
    <key>CFBundleDisplayName</key><string>Sunset Browser</string>
    <key>CFBundleIdentifier</key><string>com.carlosvp.minavegador</string>
    <key>CFBundleExecutable</key><string>Sunset Browser</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
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
