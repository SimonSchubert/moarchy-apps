# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# All five are driven by environment variables rather than by synthesised taps:
# a headless X server has no pointer worth clicking with, and a run that opens
# straight into the screen it should photograph needs none.
#
# The machine in the pictures is demo.py's -- sixty-four frames of a PinePhone
# with a browser opening a page in the middle of them, which is what puts a past
# behind the graphs. A system monitor photographed against a real container is a
# flat line and an empty list.
shot overview
shot tasks "MOARCHY_VITALS_PAGE=tasks"
shot processes "MOARCHY_VITALS_PAGE=tasks" "MOARCHY_VITALS_TASKS=all"
shot app "MOARCHY_VITALS_PICK=firefox"
shot network "MOARCHY_VITALS_PAGE=network"
