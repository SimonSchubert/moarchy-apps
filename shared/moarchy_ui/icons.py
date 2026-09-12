"""Naming an icon the theme actually has.

Naming one it does not have never fails: GTK renders "image-missing", a broken
image glyph that reads as a bug, and says nothing in any log. The app starts,
the screenshot is taken, and a grey warning triangle sits in the middle of the
empty state until somebody looks at the picture.

The phone's icon theme is not the desktop's, and that is the whole difficulty.
The dev container's theme is Adwaita; the device's is Yaru-blue.
`view-list-bullet-symbolic` and `document-edit-symbolic` are both in the first
and neither is in the second, so they passed every test and drew placeholders on
the only machine that matters.

So the chain is checked at runtime rather than assumed, and an app names the
icon it wants followed by whatever it will settle for.

This started in Keep and was the second app's problem before it was shared --
Habits named two icons Keep already knew were unsafe. `scripts/icon-check.sh`
audits the literal names against the running guest; this is the half that copes
when the audit is not run.
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")

from gi.repository import Gdk, Gtk  # noqa: E402

# The last resort. Present in every theme worth the name, and shaped like an
# explanation rather than an error.
FALLBACK = "dialog-information-symbolic"


def icon(*candidates: str) -> str:
    """First of these icon names the live theme actually has."""
    display = Gdk.Display.get_default()
    if display is None:
        # No display yet: nothing can be looked up, and the caller is almost
        # certainly building widgets before realising them. Prefer the last
        # candidate, which is the one the caller chose as its safest.
        return candidates[-1] if candidates else FALLBACK
    icons = Gtk.IconTheme.get_for_display(display)
    for name in candidates:
        if icons.has_icon(name):
            return name
    return FALLBACK
