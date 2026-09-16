# Which screens to photograph. The harness is scripts/qml-shot.sh.
#
# The catalogue is one scrolling page and the picture of it is the review
# surface for the whole kit: if a control here is wrong, it is wrong in eleven
# apps. The second and third shots are the same page in a theme that is not
# ours, which is the only way to see that nothing on it is a hardcoded colour.
THEMES="${THEMES:-/tmp/omarchy-themes}"

shot catalog
shot boxes MOARCHY_CATALOG_PAGE=boxes
shot empty MOARCHY_CATALOG_PAGE=empty

[[ -f $THEMES/tokyo-night/colors.toml ]] && \
  shot tokyo-night "THEME=$THEMES/tokyo-night/colors.toml"
[[ -f $THEMES/catppuccin-latte/colors.toml ]] && \
  shot catppuccin-latte "THEME=$THEMES/catppuccin-latte/colors.toml"
