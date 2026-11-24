#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEMP_DIR="$(mktemp -d -t aura-deps)"
MOUNT_DIR="$TEMP_DIR/mounted"
cleanup() { hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true; rm -rf "$TEMP_DIR"; }
trap cleanup EXIT
curl --fail --location --retry 2 https://github.com/iina/iina/releases/download/v1.5.0/IINA.v1.5.0.dmg -o "$TEMP_DIR/IINA.dmg"
echo "8fad50479b10e09645053457cec46bd53d054ced2242cfe68f74586735a20dc7  $TEMP_DIR/IINA.dmg" | shasum -a 256 -c -
mkdir -p "$MOUNT_DIR" Dependencies
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$TEMP_DIR/IINA.dmg"
cp "$MOUNT_DIR/IINA.app/Contents/Frameworks/"*.dylib Dependencies/
echo "mpv ve codec kitaplıkları hazır. IINA uygulama kodu veya arayüzü kopyalanmadı."
