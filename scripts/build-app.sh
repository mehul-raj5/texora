#!/bin/zsh
# Builds Texora.app (arm64, release) into dist/. Optional flags:
#   --install   copy the app to /Applications
#   --dmg       also produce dist/Texora.dmg
#   --debug     build the debug configuration instead of release
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

CONFIG=release
INSTALL=0
DMG=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --dmg) DMG=1 ;;
    --debug) CONFIG=debug ;;
  esac
done

VERSION="${TEXORA_VERSION:-$(cat VERSION 2>/dev/null || echo 1.0.0)}"
BUILD_NUM="$(date +%Y%m%d%H%M)"

echo "▸ Building ($CONFIG, arm64)…"
swift build -c "$CONFIG" --arch arm64 2>&1 | grep -Ev "^\[[0-9]+/[0-9]+\]" || true
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Texora"
[[ -x "$BIN" ]] || { echo "Build failed: $BIN missing"; exit 1; }

APP="dist/Texora.app"
echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Texora"
cp -R Resources/editor "$APP/Contents/Resources/editor"
cp -R Resources/Templates "$APP/Contents/Resources/Templates"
if [[ ! -f Resources/AppIcon.icns ]]; then
  echo "▸ Generating app icon"
  TMP="$(mktemp -d)"; swift scripts/make-icon.swift "$TMP/icon.png"
  mkdir -p "$TMP/AppIcon.iconset"
  for sz in 16 32 128 256 512; do
    sips -z $sz $sz "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${sz}x${sz}.png" >/dev/null
    sips -z $((sz*2)) $((sz*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
  done
  iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Texora</string>
  <key>CFBundleDisplayName</key><string>Texora</string>
  <key>CFBundleIdentifier</key><string>app.texora.Texora</string>
  <key>CFBundleExecutable</key><string>Texora</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUM}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSDocumentsFolderUsageDescription</key><string>Texora keeps your LaTeX projects in your Documents folder.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Texora opens LaTeX projects that live on your Desktop.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Texora imports project ZIPs from your Downloads folder.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>ZIP archive</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.zip-archive</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>Folder</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.folder</string></array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>TeX document</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>CFBundleTypeExtensions</key><array><string>tex</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "▸ Signing (ad-hoc)"
# Extended attributes (Finder info, provenance) break strict signature checks.
xattr -cr "$APP"
# Ad-hoc signatures are identified by their exact code hash, so macOS would treat every build as a new
# app and ask for folder permissions again. A designated requirement on the bundle identifier keeps the
# identity stable across builds, so permissions granted once stay granted.
codesign --force --deep --sign - --identifier app.texora.Texora \
  --requirements '=designated => identifier "app.texora.Texora"' "$APP" >/dev/null
codesign --verify --deep --strict "$APP"

if [[ $INSTALL == 1 ]]; then
  echo "▸ Installing to /Applications"
  rm -rf /Applications/Texora.app
  cp -R "$APP" /Applications/Texora.app
fi

if [[ $DMG == 1 ]]; then
  echo "▸ Creating dist/Texora.dmg"
  rm -f dist/Texora.dmg
  STAGE="$(mktemp -d)"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname Texora -srcfolder "$STAGE" -ov -format UDZO dist/Texora.dmg >/dev/null
  rm -rf "$STAGE"
fi

du -sh "$APP" | awk '{print "▸ Done: " $2 " (" $1 ")"}'
