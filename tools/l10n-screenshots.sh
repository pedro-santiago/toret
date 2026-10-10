#!/bin/zsh
# Screenshots of every screen in every language, to look for truncation and overflow.
#
#   tools/l10n-screenshots.sh [udid]            pt-BR, en and it
#   LANGS="it" DOUBLE=1 tools/l10n-screenshots.sh   Italian with every string doubled
#                                                   (-NSDoubleLocalizedStrings YES): a
#                                                   cheap stress test for long languages
#
# Needs a debug build installed on the simulator (xcodebuild ... -derivedDataPath build/i18n,
# then xcrun simctl install). Output: build/l10n/<lang>/<screen>.png
set -eu
cd "$(dirname "$0")/.."
UDID="${1:-$(xcrun simctl list devices | grep -F 'Toret i18n (' | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')}"
BUNDLE=br.tec.nuance.toret
LANGS=(${=LANGS:-pt-BR en it})
SCREENS=(${=SCREENS:-mapa perto salvas relatos ajustes bussola detalhe rota})

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl location "$UDID" set 45.06687,7.68316

for lang in $LANGS; do
  locale="${lang/-/_}"
  [ "$lang" = en ] && locale=en_US
  [ "$lang" = it ] && locale=it_IT
  mkdir -p "build/l10n/$lang"
  for screen in $SCREENS; do
    args=(-AppleLanguages "($lang)" -AppleLocale "$locale" -toret-screen "$screen")
    [ -n "${DOUBLE:-}" ] && args+=(-NSDoubleLocalizedStrings YES)
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "${args[@]}" >/dev/null
    sleep 3.5
    xcrun simctl io "$UDID" screenshot "build/l10n/$lang/$screen.png" 2>/dev/null
  done
  echo "$lang: ${#SCREENS} screens -> build/l10n/$lang"
done
