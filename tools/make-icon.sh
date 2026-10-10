#!/bin/sh
# Renders the app icon from Shared/DesignSystem/AppIconArt.swift into the asset
# catalogue.
#
#   tools/make-icon.sh [simulator name or UDID]
#
# The art is SwiftUI, so it is rendered by a test (ToretTests/IconRenderTests)
# inside the app host; TEST_RUNNER_TORET_ICON_OUT is how the output directory
# reaches that process. The PNGs are checked in: run this only when AppIconArt
# changes.
set -eu
cd "$(dirname "$0")/.."

SIM="${1:-iPhone 17 Pro}"
OUT="$(pwd)/Toret/Resources/Assets.xcassets/AppIcon.appiconset"

xcodegen generate --quiet
TEST_RUNNER_TORET_ICON_OUT="$OUT" xcodebuild test -project Toret.xcodeproj -scheme Toret \
  -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath build/icon \
  -only-testing:ToretTests/IconRenderTests -quiet

for f in "$OUT"/icon-1024*.png; do
  printf '%s: ' "$(basename "$f")"
  sips -g pixelWidth -g hasAlpha "$f" | tail -2 | tr '\n' ' '
  echo
done
