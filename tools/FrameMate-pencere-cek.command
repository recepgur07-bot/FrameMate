#!/bin/zsh
set -euo pipefail

OUT_DIR="$HOME/Desktop/FrameMate Ekran Goruntuleri"
mkdir -p "$OUT_DIR"

echo "FrameMate pencere cekimi"
echo
echo "1. FrameMate'te cekmek istedigin ekrana git."
echo "2. FrameMate penceresine bir kez tikla; pencere onde olsun."
echo "3. Buraya donup Enter'a bas."
echo
read "?Hazir olunca Enter'a bas..."

timestamp=$(/bin/date +"%Y-%m-%d_%H-%M-%S")
target="$OUT_DIR/FrameMate-$timestamp.png"

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
  let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
  let width = bounds["Width"] as? Double ?? 0
  let height = bounds["Height"] as? Double ?? 0
  return owner == "FrameMate" && layer == 0 && alpha > 0 && width > 100 && height > 100
}

guard let first = windows.first,
      let number = first[kCGWindowNumber as String] as? UInt32 else {
  exit(2)
}

print(number)
SWIFT
)

if [[ -z "$window_id" ]]; then
  echo
  echo "FrameMate penceresi bulunamadi."
  echo "FrameMate acik ve ondeyken tekrar dene."
  exit 1
fi

/usr/sbin/screencapture -x -o -l "$window_id" "$target"

if [[ ! -s "$target" ]]; then
  echo
  echo "Ekran goruntusu alinamadi."
  echo "Mac ekran kaydi izni veya FrameMate penceresini kontrol et."
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
read "?Kapatmak icin Enter'a bas..."
