# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# All five are driven by environment variables rather than by synthesised taps:
# a headless X server has no pointer worth clicking with, and a run that opens
# straight into the screen it should photograph needs none.
#
# The `stuck` shot re-seeds first, because a board with nothing left to move is
# a board that has to have been played into that state -- and the alternative,
# an app that empties its own board when an environment variable says so, would
# be a screenshot feature living in the window.
shot board
shot hint "MOARCHY_PEGSOLITAIRE_HINT=1"
shot figures "MOARCHY_PEGSOLITAIRE_FIGURES=1"
shot record "MOARCHY_PEGSOLITAIRE_PAGE=record"

python3 "apps/$app/demo.py" stuck >/dev/null
shot stuck
