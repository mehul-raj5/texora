#!/bin/zsh
# Builds dist/Texora-<version>.dmg with a drag-to-Applications window.
#   scripts/make-dmg.sh                 build the app, then the DMG
#   scripts/make-dmg.sh --skip-build    package an existing dist/Texora.app
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"

VERSION="${TEXORA_VERSION:-$(cat VERSION 2>/dev/null || echo 1.0.0)}"
if [[ "${1:-}" != "--skip-build" ]]; then
  TEXORA_VERSION="$VERSION" ./scripts/build-app.sh
fi
[[ -d dist/Texora.app ]] || { echo "dist/Texora.app missing"; exit 1; }

# dmgbuild lays out the DMG window without needing Finder (works on CI too).
VENV=".venv-dmg"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  echo "▸ Installing dmgbuild into $VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet "dmgbuild>=1.6"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "▸ Drawing the DMG background"
swift scripts/dmg/make-background.swift "$WORK"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null

OUT="dist/Texora-$VERSION.dmg"
rm -f "$OUT"
echo "▸ Building $OUT"
"$VENV/bin/dmgbuild" -s scripts/dmg/settings.py \
  -D app=dist/Texora.app -D background="$WORK/background.tiff" -D volume_icon=Resources/AppIcon.icns \
  "Texora" "$OUT"

shasum -a 256 "$OUT" | tee "$OUT.sha256"
du -h "$OUT" | awk '{print "▸ Done: " $2 " (" $1 ")"}'
