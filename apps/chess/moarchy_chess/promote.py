"""What the pawn becomes.

The one question in chess the board cannot ask on its own, and the one place
this app stops and waits for an answer. It is a sheet with four pictures on it
rather than a list of four words, because the pictures are already drawn -- the
board draws them sixteen at a time -- and because "Knight" is a word somebody
has to read while a piece of a game is on hold.

The queen is first and marked, and that is not laziness about the other three:
a promotion is a queen in all but a rounding error of games, so the tap that is
nearly always right is the one nearest the thumb, and nothing is chosen by
default. A sheet that had picked the queen and asked for confirmation would be
asking a question it had already answered.
"""

from __future__ import annotations

from typing import ClassVar

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, GObject, Gtk  # noqa: E402

from . import pieces  # noqa: E402
from .chess import BISHOP, KNIGHT, QUEEN, ROOK, piece  # noqa: E402
from .widgets import PieceIcon  # noqa: E402

CHOICES = (QUEEN, ROOK, BISHOP, KNIGHT)

# Big enough to be a target on a phone with plenty of margin: the game is
# stopped until one of these is hit, so a miss here is worse than a miss on the
# board, where a wrong tap merely selects the wrong piece.
ICON = 52


class PromotionDialog(Adw.Dialog):
    """Emits `chosen` with the kind the pawn becomes."""

    __gtype_name__ = "ChessPromotion"

    __gsignals__: ClassVar[dict] = {
        "chosen": (GObject.SignalFlags.RUN_FIRST, None, (int,)),
    }

    def __init__(self, colour: int, palette) -> None:
        super().__init__()
        self.set_title("Promote")
        self.set_content_width(360)
        self._icons: list[PieceIcon] = []

        header = Adw.HeaderBar()

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.add_css_class("promotion")
        row.set_homogeneous(True)
        row.set_margin_top(8)
        row.set_margin_bottom(20)
        row.set_margin_start(14)
        row.set_margin_end(14)
        for kind in CHOICES:
            icon = PieceIcon(piece(colour, kind), ICON)
            icon.set_colours(palette)
            self._icons.append(icon)
            button = Gtk.Button()
            button.set_child(icon)
            button.add_css_class("flat")
            button.set_tooltip_text(pieces.NAMES[kind].capitalize())
            button.update_property(
                [Gtk.AccessibleProperty.LABEL],
                [f"Promote to {pieces.NAMES[kind]}"],
            )
            if kind == QUEEN:
                button.add_css_class("suggested-action")
            button.connect("clicked", self._on_click, kind)
            row.append(button)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(row)
        self.set_child(view)

    def _on_click(self, _button, kind: int) -> None:
        self.emit("chosen", kind)
        self.close()
