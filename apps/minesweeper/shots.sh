# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# Driven by environment variables rather than by synthesised taps: a headless X
# server has no pointer worth clicking with, and a run that opens straight into
# the screen it should photograph needs none.
#
# The `lost` shot re-seeds first, because a board with a mine gone off on it has
# to have been played into that state -- and the alternative, an app that blows
# itself up when an environment variable says so, would be a screenshot feature
# living in the window.
shot board
shot marking "MOARCHY_MINESWEEPER_MARKING=1"
shot levels "MOARCHY_MINESWEEPER_NEW=1"
shot record "MOARCHY_MINESWEEPER_PAGE=record"

python3 "apps/$app/demo.py" lost >/dev/null
shot lost
