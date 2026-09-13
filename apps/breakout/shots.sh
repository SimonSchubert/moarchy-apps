# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# Driven by environment variables rather than by synthesised taps: a headless X
# server has no pointer worth clicking with, and a run that opens straight into
# the screen it should photograph needs none.
#
# `MOARCHY_BREAKOUT_SERVED` is the one hook this app needs that the others do
# not: a saved game always comes back with the ball on the bat -- deliberately,
# because a ball frozen in mid-air is not where anybody left it -- so a picture
# of a rally has to ask for the ball to be sent off and half a second of play to
# happen before the shutter.
shot board "MOARCHY_BREAKOUT_SERVED=1"
shot waiting
shot record "MOARCHY_BREAKOUT_PAGE=record"

python3 "apps/$app/demo.py" late >/dev/null
shot late "MOARCHY_BREAKOUT_SERVED=1"
