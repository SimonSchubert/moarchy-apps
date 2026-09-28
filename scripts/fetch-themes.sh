#!/bin/bash
# Fetch Omarchy's themes, so the palette work can be checked without a phone.
#
#   ./scripts/fetch-themes.sh /tmp/omarchy-themes
#   SHOTS=... scripts/app-shot.sh <app>   # with THEME=/tmp/omarchy-themes/tokyo-night/colors.toml in a shot line
#
# Pinned to the Omarchy the phone ships (omarchy-mobile's manifest.toml, v4.0.4),
# so what is checked is what the phone will have: every theme it offers.
set -uo pipefail

DEST="${1:-/tmp/omarchy-themes}"
PIN="${OMARCHY_PIN:-c668141e9c42b13c80c9ca4ea108e11708c5e8a5}"
BASE="https://raw.githubusercontent.com/omacom/omarchy/$PIN/themes"

THEMES=(
  catppuccin catppuccin-latte ethereal everforest flexoki-light gruvbox
  hackerman kanagawa last-horizon lumon lupine matte-black miasma nord
  osaka-jade retro-82 ristretto rose-pine solitude tokyo-night vantablack white
)

mkdir -p "$DEST"
missing=0
for theme in "${THEMES[@]}"; do
  mkdir -p "$DEST/$theme"
  curl -fsSL --max-time 20 "$BASE/$theme/colors.toml" -o "$DEST/$theme/colors.toml" || {
    echo "!! could not fetch $theme" >&2; missing=$((missing + 1)); }
done

echo "==> $(find "$DEST" -name colors.toml | wc -l | tr -d ' ') palettes in $DEST"
exit $(( missing > 0 ? 1 : 0 ))
