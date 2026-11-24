#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
MODE="${1:-release}"
if [[ ! -f Dependencies/libmpv.2.dylib ]]; then
  echo "mpv kitaplıkları eksik. Önce ./Scripts/fetch-dependencies.sh çalıştır."
  exit 1
fi
swift build --product Aura -c "$MODE" --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
BIN_DIR="$(swift build --show-bin-path -c "$MODE" --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security)"
STAGE_DIR="$(mktemp -d -t aura-build)"
trap 'rm -rf "$STAGE_DIR"' EXIT
APP="$STAGE_DIR/Aura.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Aura" "$APP/Contents/MacOS/Aura"
cp Info.plist "$APP/Contents/Info.plist"
ditto "$BIN_DIR/Aura_Aura.bundle" "$APP/Contents/Resources/Aura_Aura.bundle"
cp Dependencies/*.dylib "$APP/Contents/Frameworks/"
python3 Scripts/relocate-libraries.py "$APP/Contents/Frameworks"
if [[ ! -f Artwork/Aura.icns ]]; then
  swift Scripts/make-icon.swift Artwork
  python3 Scripts/make-icns.py Artwork/Aura.iconset Artwork/Aura.icns
fi
cp Artwork/Aura.icns "$APP/Contents/Resources/Aura.icns"
mkdir -p "$APP/Contents/Resources/Licenses"
cp docs/*.txt "$APP/Contents/Resources/Licenses/"
xattr -cr "$APP"
codesign --force --sign - --identifier dev.aura.player "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p dist
# Keep only the ZIP here. A second .app gets indexed as another application.
ditto -c -k --keepParent --noextattr --norsrc "$APP" "$PWD/dist/Aura-Mac.zip"
echo "Hazır: $PWD/dist/Aura-Mac.zip (imza arşivlenmeden önce doğrulandı)"
