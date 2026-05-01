#!/bin/zsh
set -euo pipefail

ROOT="/Users/recepgur/Desktop/video recorder"
OUT_DIR="$ROOT/fastlane/screenshots_raw/mac"
mkdir -p "$OUT_DIR"

choice=$(/usr/bin/osascript <<'APPLESCRIPT'
set screenNames to {"01_Record_Everything", "02_Presentations_Lessons", "03_Flexible_Modes", "04_Frame_Coach", "05_Customize_Settings", "06_Preview_Save"}
set picked to choose from list screenNames with title "FrameMate App Store" with prompt "Hangi ekran goruntusunu kaydediyoruz?" default items {"01_Record_Everything"}
if picked is false then
  return ""
end if
return item 1 of picked
APPLESCRIPT
)

if [[ -z "$choice" ]]; then
  exit 0
fi

target="$OUT_DIR/$choice.png"

/usr/bin/osascript <<'APPLESCRIPT'
set messageText to "Simdi pencere secme modu acilacak." & return & return & "Yapman gereken:" & return & "1. Imlec kamera gibi olunca FrameMate penceresine gotur." & return & "2. Sadece buyuk FrameMate penceresi vurgulaninca tikla." & return & return & "Sol taraftaki kucuk onizlemelere tiklama."
display dialog messageText buttons {"Pencere sececegim"} default button 1 with title "FrameMate ekran goruntusu"
APPLESCRIPT

/usr/sbin/screencapture -i -w -o "$target"

if [[ ! -s "$target" ]]; then
  /usr/bin/osascript -e 'display alert "Ekran goruntusu alinamadi." message "macOS ekran kaydi iznini veya tikladigin pencereyi kontrol et."'
  exit 1
fi

size=$(/opt/homebrew/bin/magick identify -format '%wx%h' "$target" 2>/dev/null || /usr/bin/sips -g pixelWidth -g pixelHeight "$target")
/usr/bin/osascript -e "display notification \"$choice.png kaydedildi ($size).\" with title \"FrameMate ekran goruntusu\""
