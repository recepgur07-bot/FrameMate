#!/bin/zsh
set -euo pipefail

ROOT="/Users/recepgur/Desktop/video recorder"
TARGET="$ROOT/fastlane/screenshots_raw/mac/01_Record_Everything.png"
mkdir -p "$(dirname "$TARGET")"

echo "FrameMate ilk App Store ham ekran goruntusu alinacak."
echo
echo "Birazdan macOS pencere secme modu acilacak."
echo "Imlec kamera gibi olunca FrameMate ana penceresine tikla."
echo "Dosya buraya kaydedilecek:"
echo "$TARGET"
echo
read "?Hazir olunca Enter'a bas..."

/usr/sbin/screencapture -i -w -o "$TARGET"

if [[ ! -s "$TARGET" ]]; then
  echo "Ekran goruntusu alinamadi."
  exit 1
fi

if [[ -x /opt/homebrew/bin/magick ]]; then
  size=$(/opt/homebrew/bin/magick identify -format '%wx%h' "$TARGET")
else
  size=$(/usr/bin/sips -g pixelWidth -g pixelHeight "$TARGET" | awk '/pixel/ {print $2}' | paste -sdx -)
fi

echo
echo "Kaydedildi: $TARGET"
echo "Boyut: $size"
echo
read "?Kapatmak icin Enter'a bas..."
