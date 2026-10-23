#!/bin/zsh
set -eu
cd "${0:A:h}"
icon_dir=$(mktemp -d "${TMPDIR:-/tmp}/burst-icon.XXXXXX")
trap 'rm -rf "$icon_dir"' EXIT
mkdir -p "$icon_dir/AppIcon.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon.png --out "$icon_dir/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" Assets/AppIcon.png --out "$icon_dir/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
mkdir -p dist
iconutil -c icns "$icon_dir/AppIcon.iconset" -o dist/AppIcon.icns
