# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# All four are driven by environment variables rather than by synthesised taps:
# a headless X server has no pointer worth clicking with, and a run that opens
# straight into the screen it should photograph needs none.
#
# The `won` shot re-seeds first, because the line struck through three in a row
# is the one thing this app draws that a board in progress cannot show, and the
# alternative -- an app that finishes its own game when an environment variable
# says so -- would be a screenshot feature living in the window.
shot board
shot record "MOARCHY_TICTACTOE_PAGE=record"
shot newgame "MOARCHY_TICTACTOE_NEW=1"

python3 "apps/$app/demo.py" won >/dev/null
shot won
