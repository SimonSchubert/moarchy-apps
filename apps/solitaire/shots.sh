# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# All four are driven by environment variables rather than by synthesised taps:
# a headless X server has no pointer worth clicking with, and a run that opens
# straight into the screen it should photograph needs none.
#
# The `home` shot re-seeds first, because the banner only appears on a table
# with nothing left face down -- and the alternative, an app that finishes its
# own deal when an environment variable says so, would be a screenshot feature
# living in the window.
shot table
shot picked "MOARCHY_SOLITAIRE_PICK=auto"
shot record "MOARCHY_SOLITAIRE_PAGE=record"
shot newdeal "MOARCHY_SOLITAIRE_NEW=1"

python3 "apps/$app/demo.py" home >/dev/null
shot home
