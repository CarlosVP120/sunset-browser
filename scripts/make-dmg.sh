#!/bin/zsh
# Crea el instalador build/Sunset-Browser.dmg: una ventana con el cielo de Sunset donde se
# arrastra la app a Aplicaciones (como el de Arc).
set -euo pipefail

cd "$(dirname "$0")/.."
NAME="Sunset Browser"
DMG="build/Sunset-Browser.dmg"
WORK="$(mktemp -d)"
STAGING="$WORK/staging"
trap 'hdiutil detach "/Volumes/$NAME" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

# 1. La app en versión optimizada (SKIP_BUILD=1 reutiliza la ya empaquetada).
[[ "${SKIP_BUILD:-0}" == 1 ]] || ./scripts/bundle.sh release

# 2. Contenido del disco: la app, un acceso a Aplicaciones y el fondo (oculto).
mkdir -p "$STAGING/.background"
cp -R "build/$NAME.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
swift scripts/dmg-background.swift "$WORK/bg.png" 1 >/dev/null
swift scripts/dmg-background.swift "$WORK/bg@2x.png" 2 >/dev/null
# TIFF con las dos resoluciones: nítido en pantallas Retina y normales.
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$STAGING/.background/background.tiff" >/dev/null 2>&1
# Icono del disco: el mismo de la app.
cp "build/$NAME.app/Contents/Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"

# 3. Disco editable para colocar los iconos.
hdiutil detach "/Volumes/$NAME" -quiet 2>/dev/null || true
hdiutil create -quiet -srcfolder "$STAGING" -volname "$NAME" -fs HFS+ -format UDRW -size 200m "$WORK/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$WORK/rw.dmg"
SetFile -a C "/Volumes/$NAME" 2>/dev/null || true
# Que la ventana se abra sola al montar el disco.
bless --folder "/Volumes/$NAME" --openfolder "/Volumes/$NAME" 2>/dev/null || true

# 4. Finder: ventana sin barras, iconos grandes y el fondo (las posiciones coinciden con el dibujo).
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        try
            set pathbar visible of container window to false
        end try
        set sidebar width of container window to 0
        set bounds of container window to {200, 120, 840, 568}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "$NAME.app" of container window to {176, 158}
        set position of item "Applications" of container window to {464, 158}
        update without registering applications
        delay 1
        close
        -- Se vuelve a abrir para que Finder guarde el tamaño definitivo de la ventana.
        open
        set bounds of container window to {200, 120, 840, 568}
        delay 1
        close
    end tell
end tell
APPLESCRIPT
sync
hdiutil detach -quiet "/Volumes/$NAME"

# 5. Versión final comprimida y de solo lectura.
rm -f "$DMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
echo "Listo: $DMG ($(du -h "$DMG" | cut -f1))"
