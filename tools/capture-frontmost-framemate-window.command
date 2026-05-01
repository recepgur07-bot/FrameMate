#!/bin/zsh
set -euo pipefail

ROOT="/Users/recepgur/Desktop/video recorder"
OUT_DIR="$ROOT/fastlane/screenshots_raw/mac"
mkdir -p "$OUT_DIR"

SCREEN_NAMES=(
  "01_Record_Everything"
  "02_Presentations_Lessons"
  "03_Flexible_Modes"
  "04_Frame_Coach"
  "05_Customize_Settings"
  "06_Preview_Save"
)

echo "FrameMate ondeki pencere yakalama"
echo
echo "Once FrameMate'te cekmek istedigin ekrani one getir."
echo "Sonra asagidaki numaralardan hangisi oldugunu sec."
echo

for i in {1..6}; do
  echo "$i) ${SCREEN_NAMES[$i]}"
done

echo
read "?Hangi ekran? 1-6: " choice

if ! [[ "$choice" =~ '^[1-6]$' ]]; then
  echo "Gecersiz secim."
  exit 1
fi

key="${SCREEN_NAMES[$choice]}"
target="$OUT_DIR/$key.png"

front_app=$(/usr/bin/osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')
if [[ "$front_app" != "FrameMate" ]]; then
  echo
  echo "FrameMate su anda onde degil. Onde olan uygulama: $front_app"
  echo "FrameMate penceresine tikla ve bu kestirmeyi tekrar calistir."
  exit 1
fi

window_id=$(CLANG_MODULE_CACHE_PATH=/tmp/codex-swift-module-cache swift -module-cache-path /tmp/codex-swift-module-cache <<'SWIFT'
import Foundation
import CoreGraphics

let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
  exit(1)
}

let windows = rawList.filter { window in
  let owner = window[kCGWindowOwnerName as String] as? String ?? ""
  let layer = window[kCGWindowLayer as String] as? Int ?? -1
  let alpha = window[kCGWindowAlpha as String] as? Double ?? 0
  return owner == "FrameMate" && layer == 0 && alpha > 0
}

guard let first = windows.first,
      let number = first[kCGWindowNumber as String] as? UInt32 else {
  exit(2)
}

print(number)
SWIFT
)

if [[ -z "$window_id" ]]; then
  echo "FrameMate pencere numarasi bulunamadi."
  exit 1
fi

/usr/sbin/screencapture -x -o -l "$window_id" "$target"

if [[ ! -s "$target" ]]; then
  echo "Ekran goruntusu alinamadi."
  exit 1
fi

if [[ -x /opt/homebrew/bin/magick ]]; then
  size=$(/opt/homebrew/bin/magick identify -format '%wx%h' "$target")
else
  size=$(/usr/bin/sips -g pixelWidth -g pixelHeight "$target" | awk '/pixel/ {print $2}' | paste -sdx -)
fi

echo
echo "Kaydedildi:"
echo "$target"
echo "Boyut: $size"
echo
