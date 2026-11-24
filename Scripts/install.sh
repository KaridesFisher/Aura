#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
INSTALL_DIR="${AURA_INSTALL_DIR:-/Applications}"
TEMP_DIR="$(mktemp -d -t aura-install)"
trap 'rm -rf "$TEMP_DIR"' EXIT
if [[ ! -f dist/Aura-Mac.zip ]]; then echo "Önce ./Scripts/build.sh çalıştır."; exit 1; fi
if [[ -d "$INSTALL_DIR/Aura.app" ]]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_DIR/Aura.app/Contents/Info.plist")"
  if [[ "$EXISTING_ID" != dev.aura.player ]]; then echo "Başka bir Aura uygulamasının üzerine yazılmadı."; exit 1; fi
fi
ditto -x -k --noextattr --norsrc dist/Aura-Mac.zip "$TEMP_DIR"
codesign --verify --deep --strict "$TEMP_DIR/Aura.app"
mkdir -p "$INSTALL_DIR"
ditto --noextattr --norsrc "$TEMP_DIR/Aura.app" "$INSTALL_DIR/Aura.app"
codesign --verify --deep --strict "$INSTALL_DIR/Aura.app"
echo "Kuruldu: $INSTALL_DIR/Aura.app"
