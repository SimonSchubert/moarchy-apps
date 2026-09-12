# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# All four are driven by environment variables rather than by synthesised taps:
# a headless X server has no pointer worth clicking with, and a run that opens
# straight into the screen it should photograph needs none. demo.py leaves a
# real game in progress with White -- the person -- to move, so the board shot
# has something on it worth looking at and the held shot has somewhere to go.
shot board
shot held "MOARCHY_CHESS_SELECT=auto"
shot record "MOARCHY_CHESS_PAGE=record"
shot newgame "MOARCHY_CHESS_NEW=1"
