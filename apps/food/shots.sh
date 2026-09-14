# What to photograph. Run by scripts/screenshot.sh with shot, shot_click and
# shot_longpress already defined.
#
# Every one of them sets MOARCHY_FOOD_OFFLINE, and that is the whole trick to
# photographing this app. With it the window shows the products demo.py wrote
# and never opens a socket, so the pictures are the same on a laptop, in the
# container and on a machine with no route to the internet at all.
#
# The scanner is a camera. A headless X server has none, so the scan shot is
# the empty state that says so -- which is a real screen, not a stand-in.
# Pointing MOARCHY_FOOD_PREVIEW at demo.py's barcode PNG would need GStreamer
# in the screenshot container; the product page is the one that has to be
# right, and it does not.
shot scan "MOARCHY_FOOD_OFFLINE=1" "MOARCHY_FOOD_CAMERA=0"
shot product "MOARCHY_FOOD_OFFLINE=1" "MOARCHY_FOOD_PAGE=product"
shot history "MOARCHY_FOOD_OFFLINE=1" "MOARCHY_FOOD_PAGE=history"
shot missing "MOARCHY_FOOD_OFFLINE=1" "MOARCHY_FOOD_PAGE=missing" "MOARCHY_FOOD_CODE=0000000000000"
