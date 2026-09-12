# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# All three are driven by environment variables rather than by synthesised taps:
# a headless X server has no pointer worth clicking with, and a run that opens
# straight into the screen it should photograph needs none. demo.py leaves a
# real game in progress with dark -- the person -- to move, so the board shot
# has hints on it.
shot board
shot record "MOARCHY_REVERSI_PAGE=record"
shot newgame "MOARCHY_REVERSI_NEW=1"
