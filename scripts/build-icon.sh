#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="$PWD/Assets/MawChatIcon.png"
ICONSET="$PWD/build/MawChatIcon.iconset"
OUTPUT="${1:-$PWD/build/MawChatIcon.icns}"
mkdir -p "$ICONSET" "$(dirname "$OUTPUT")"
# Package the original transparent artwork at the standard macOS icon sizes.
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil --convert icns "$ICONSET" --output "$OUTPUT"
