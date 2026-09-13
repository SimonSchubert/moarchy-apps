# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# All five are driven by environment variables rather than by synthesised taps:
# a headless X server has no pointer worth clicking with, and a run that opens
# straight into the screen it should photograph needs none.
#
# The `take` shot re-seeds first, because a board with a mill just closed on it
# has to have been played into that state -- and the alternative, an app that
# hands itself a mill when an environment variable says so, would be a
# screenshot feature living in the window.
shot board
shot picked "MOARCHY_MILL_PICK=1"
shot record "MOARCHY_MILL_PAGE=record"
shot newgame "MOARCHY_MILL_NEW=1"

python3 "apps/$app/demo.py" take >/dev/null
shot take
