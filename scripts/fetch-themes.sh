#!/bin/bash
# Fetch Omarchy's themes, so the palette work can be checked without a phone.
#
#   ./scripts/fetch-themes.sh /tmp/omarchy-themes
#   THEME=/tmp/omarchy-themes/tokyo-night/colors.toml ./scripts/screenshot.sh
#
# Pinned to the commit mobileomarchy vendors, so what is checked is what the
# phone will have.
set -uo pipefail

DEST="${1:-/tmp/omarchy-themes}"
PIN="${OMARCHY_PIN:-346e69e1cec6c4e8924531874af6ba010a1bc99e}"
BASE="https://raw.githubusercontent.com/basecamp/omarchy/$PIN/themes"

THEMES=(
  catppuccin catppuccin-latte everforest gruvbox kanagawa matte-black nord
  osaka-jade rose-pine tokyo-night
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
