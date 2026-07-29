#!/usr/bin/env bash
# Salt-okunur macOS proje kalite kapısı. Formatlama, upload veya ASC erişimi yapmaz.

set -euo pipefail

usage() {
  echo "Kullanım: $0 --project VideoRecorder.xcodeproj --scheme FrameMate --destination 'platform=macOS'" >&2
  exit 2
}

project=""
scheme=""
destination=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project) project=${2:-}; shift 2 ;;
    --scheme) scheme=${2:-}; shift 2 ;;
    --destination) destination=${2:-}; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$project" ] && [ -n "$scheme" ] && [ -n "$destination" ] || usage

command -v gitleaks >/dev/null 2>&1 || { echo "gitleaks bulunamadı" >&2; exit 2; }
command -v xcbeautify >/dev/null 2>&1 || { echo "xcbeautify bulunamadı" >&2; exit 2; }
command -v ruby >/dev/null 2>&1 || { echo "ruby bulunamadı" >&2; exit 2; }
command -v magick >/dev/null 2>&1 || { echo "ImageMagick (magick) bulunamadı" >&2; exit 2; }

gitleaks git . --redact=100 --no-banner

if [ -f .swiftformat ]; then
  command -v swiftformat >/dev/null 2>&1 || { echo "SwiftFormat bulunamadı" >&2; exit 2; }
  swiftformat --lint .
fi

if [ -f .swiftlint.yml ]; then
  command -v swiftlint >/dev/null 2>&1 || { echo "SwiftLint bulunamadı" >&2; exit 2; }
  swiftlint lint --quiet
fi

xcodebuild test -project "$project" -scheme "$scheme" -destination "$destination" | xcbeautify
ruby -E UTF-8 Tests/FrameCoachLocalizationCatalogTests.rb
ruby Tests/StoreScreenshotStylerTests.rb
