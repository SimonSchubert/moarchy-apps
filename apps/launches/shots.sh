# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# Every one of them sets MOARCHY_LAUNCHES_OFFLINE and MOARCHY_LAUNCHES_NOW, and
# that is the whole trick to photographing this app. With them the window shows
# the pad demo.py wrote and never opens a socket, and the countdown in the
# pictures is T-00:12:00 every time -- so two shots taken a minute apart still
# agree.
#
# The rest is environment variables rather than synthesised taps: a headless X
# server has no pointer worth clicking with, and a run that opens straight into
# the screen it should photograph needs none.

NOW="MOARCHY_LAUNCHES_NOW=2026-09-14T18:00:00Z"

shot upcoming "MOARCHY_LAUNCHES_OFFLINE=1" "$NOW"
shot starred "MOARCHY_LAUNCHES_OFFLINE=1" "$NOW" "MOARCHY_LAUNCHES_PAGE=favourites"
shot search "MOARCHY_LAUNCHES_OFFLINE=1" "$NOW" "MOARCHY_LAUNCHES_SEARCH=falcon"
shot detail "MOARCHY_LAUNCHES_OFFLINE=1" "$NOW" "MOARCHY_LAUNCHES_PAGE=detail" "MOARCHY_LAUNCHES_OPEN=vega-sentinel"
