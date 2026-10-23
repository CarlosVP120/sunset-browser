#!/bin/zsh
# Compila Sunset Browser y lo empaqueta como "build/Sunset Browser.app"
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"

# UNIVERSAL=1: Apple Silicon e Intel en el mismo binario (para compartir la app).
ARCH_FLAGS=()
[[ "${UNIVERSAL:-0}" == 1 ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)/MiNavegador"

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
    <!-- Para poder ser el navegador predeterminado: abre enlaces web y archivos HTML. -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>Web</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>CFBundleURLSchemes</key><array><string>http</string><string>https</string></array>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Página web</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Default</string>
            <key>LSItemContentTypes</key><array><string>public.html</string><string>public.xhtml</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Firma. Sin identidad, firma local (ad hoc): todo funciona menos las llaves de acceso (passkeys).
# Con SUNSET_SIGN_IDENTITY="Developer ID Application: …" y SUNSET_PROFILE=<perfil .provisionprofile
# con el permiso de navegador>, se firma con los permisos de Resources/SunsetBrowser.entitlements.
if [[ -n "${SUNSET_SIGN_IDENTITY:-}" ]]; then
    [[ -n "${SUNSET_PROFILE:-}" ]] && cp "$SUNSET_PROFILE" "$APP/Contents/embedded.provisionprofile"
    codesign --force --options runtime --timestamp --entitlements Resources/SunsetBrowser.entitlements \
        --sign "$SUNSET_SIGN_IDENTITY" "$APP" >/dev/null
else
    codesign --force --sign - "$APP" >/dev/null
fi
echo "Listo: $APP"
