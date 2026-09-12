# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# Most are driven by MOARCHY_KEEP_OPEN rather than by synthesised taps: a
# headless X server has no pointer worth clicking with, and a run that opens
# straight into the note it should photograph needs none. The two that do tap
# are a popover and a long press, neither of which an environment variable can
# open.
shot grid
shot_longpress card-menu 90 130
shot note-list "MOARCHY_KEEP_OPEN=Shopping"
shot note-text "MOARCHY_KEEP_OPEN=Sourdough"
shot_click colours "${COLOUR_BUTTON_X:-178}" 28 "MOARCHY_KEEP_OPEN=Sourdough"
