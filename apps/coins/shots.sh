# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# Every one of them sets MOARCHY_COINS_OFFLINE, and that is the whole trick to
# photographing this app. With it the window shows the market demo.py wrote and
# never opens a socket, so the pictures are the same on a laptop, in the
# container and on a machine with no route to the internet at all -- and the
# prices in them do not move between one shot and the next.
#
# The rest is environment variables rather than synthesised taps: a headless X
# server has no pointer worth clicking with, and a run that opens straight into
# the screen it should photograph needs none.
shot market "MOARCHY_COINS_OFFLINE=1"
shot starred "MOARCHY_COINS_OFFLINE=1" "MOARCHY_COINS_PAGE=favourites"
shot search "MOARCHY_COINS_OFFLINE=1" "MOARCHY_COINS_SEARCH=bit"
