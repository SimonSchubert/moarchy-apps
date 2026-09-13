# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# Driven by environment variables rather than by synthesised taps: a headless X
# server has no pointer worth clicking with, and a run that opens straight into
# the screen it should photograph needs none. The day is pinned by the harness,
# which is what makes the word in the picture the same word every time.
#
# The `solved` shot re-seeds first, because a finished board has to have been
# played into that state -- and the alternative, an app that finishes its own
# day when an environment variable says so, would be a screenshot feature living
# in the window.
shot board "MOARCHY_FIVELETTERS_TYPED=SPINE"
shot record "MOARCHY_FIVELETTERS_PAGE=record"

python3 "apps/$app/demo.py" solved >/dev/null
shot solved
