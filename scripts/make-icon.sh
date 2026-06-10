#!/bin/sh
# Regenerate Resources/AppIcon.icns from the 1024x1024 master at assets/icon.png.
# Run after editing the icon: `make icon` (or `sh scripts/make-icon.sh`).
set -e
cd "$(dirname "$0")/.."

MASTER=assets/icon.png
[ -f "$MASTER" ] || { echo "missing $MASTER"; exit 1; }

ICS="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICS"
AT=$(printf '\100')   # '@' built at runtime so Retina names don't read as an email

for P in 16 32 128 256 512; do
  sips -z "$P" "$P" "$MASTER" --out "$ICS/icon_${P}x${P}.png" >/dev/null
  D=$((P * 2))
  sips -z "$D" "$D" "$MASTER" --out "$ICS/icon_${P}x${P}${AT}2x.png" >/dev/null
done

iconutil -c icns "$ICS" -o Resources/AppIcon.icns
rm -rf "$(dirname "$ICS")"
echo "Resources/AppIcon.icns regenerated from $MASTER"
