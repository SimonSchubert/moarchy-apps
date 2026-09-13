"""Thirty tiles, and the keyboard under them.

The board is one Gtk.DrawingArea and the keyboard is twenty-eight real buttons,
and the split is not arbitrary. A tile has to **flip** -- the reveal is the whole
theatre of this game, and it is a transform on a shape rather than a change of
state -- while a key has to look **pressed**, which GTK already does better on a
touch screen than a draw function would, and has to take a tap on a 36px target,
which is a job for something with a real hit area and a real focus ring.

The tiles carry a mark as well as a colour: a filled dot in the corner of a
letter that is in the right place, an open ring for one that is in the word
somewhere else, and nothing at all for one that is not. The colours are the
rules in this game and always have been, but one arc per tile is the difference
between a playable board and an unplayable one for about one man in twelve.

The size arithmetic: 360px of screen, 5 tiles, 6px between them, leaves 62px a
tile at the widest and the cap brings it to 58 -- because the keyboard below
wants 150 of the 720, the header wants 48, and a board that took everything left
would put the top row under the title.
"""

from __future__ import annotations

import math
from typing import ClassVar

import cairo
import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import GLib, GObject, Gtk  # noqa: E402

from . import theme  # noqa: E402
from .fiveletters import ABSENT, CORRECT, PRESENT, Game  # noqa: E402
from .words import GUESSES, KEYBOARD, LENGTH  # noqa: E402

# One tile turning over, and how far apart the five of them start. The stagger
# is what makes a row read left to right rather than all at once, which is the
# order somebody reads a word in.
FLIP_MS = 280.0
STAGGER_MS = 110.0

# A row refusing a word. Short, sharp, and back where it started.
SHAKE_MS = 380.0
SHAKE_SWING = 7.0

GAP = 6.0
ROUND = 0.14
LETTER = 0.52
MARK = 0.115

MINIMUM_TILE = 34
MAXIMUM_TILE = 58


def _rounded(cr, x: float, y: float, w: float, h: float, radius: float) -> None:
    radius = min(radius, w / 2, h / 2)
    cr.new_sub_path()
    cr.arc(x + w - radius, y + radius, radius, -math.pi / 2, 0)
    cr.arc(x + w - radius, y + h - radius, radius, 0, math.pi / 2)
    cr.arc(x + radius, y + h - radius, radius, math.pi / 2, math.pi)
    cr.arc(x + radius, y + radius, radius, math.pi, 3 * math.pi / 2)
    cr.close_path()


class BoardView(Gtk.DrawingArea):
    """Six rows of five, drawn once per frame that needs one."""

    __gtype_name__ = "FiveLettersBoardView"

    __gsignals__: ClassVar[dict] = {
        # Everything that was moving has stopped. The window waits for this
        # before it says whether the game is over, so that the sentence does not
        # arrive before the row it is about.
        "settled": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self) -> None:
        super().__init__()
        self._game: Game | None = None
        self._typed = ""
        self._anim: dict | None = None
        self._tick = 0
        self.set_hexpand(True)
        self.set_draw_func(self._draw)
        self.set_colours(theme.fallback(dark=True))

    def do_get_request_mode(self) -> Gtk.SizeRequestMode:
        return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH

    def do_measure(self, orientation, for_size: int) -> tuple:
        if orientation == Gtk.Orientation.HORIZONTAL:
            width = int(LENGTH * MINIMUM_TILE + (LENGTH - 1) * GAP)
            return width, width, -1, -1
        tile = self._tile_for(for_size)
        height = int(GUESSES * tile + (GUESSES - 1) * GAP)
        return height, height, -1, -1

    def _tile_for(self, width: float) -> float:
        tile = (width - (LENGTH - 1) * GAP) / LENGTH
        return min(max(tile, MINIMUM_TILE), MAXIMUM_TILE)

    # --- what to draw ----------------------------------------------------

    def set_colours(self, palette: theme.Palette) -> None:
        colours = theme.board_colours(palette)
        self._ink = {n: theme.rgb(value) for n, value in vars(colours).items()}
        self.queue_draw()

    def show(self, game: Game, typed: str = "") -> None:
        self._game = game
        self._typed = typed.upper()
        self.update_property([Gtk.AccessibleProperty.LABEL], [self.describe()])
        self.queue_draw()

    def describe(self) -> str:
        game = self._game
        if game is None:
            return "Board"
        if game.solved:
            return f"Board, solved in {game.used}"
        if game.out:
            return f"Board, out of guesses, the word was {game.secret}"
        rows = ", ".join(guess.word for guess in game.guesses) or "nothing yet"
        return f"Board, {game.left} guesses left. Guessed: {rows}"

    # --- moving ----------------------------------------------------------

    def reveal(self, row: int) -> None:
        """Turn a row of tiles over, one after another."""
        self._start({"kind": "flip", "row": row})

    def refuse(self, row: int) -> None:
        """Shake a row that will not be accepted."""
        self._start({"kind": "shake", "row": row})

    def _start(self, anim: dict) -> None:
        self._stop()
        if not self._motion_wanted():
            # Reduced motion is a setting people turn on because motion makes
            # them ill. The row still lands, it simply lands at once -- and a
            # refusal that cannot shake is said in words instead, which the
            # window does anyway.
            self.queue_draw()
            GLib.idle_add(self._settle)
            return
        anim["start"] = 0
        anim["length"] = (
            FLIP_MS + STAGGER_MS * (LENGTH - 1) if anim["kind"] == "flip" else SHAKE_MS
        )
        self._anim = anim
        self._tick = self.add_tick_callback(self._frame)

    def _motion_wanted(self) -> bool:
        settings = Gtk.Settings.get_default()
        return settings is None or settings.props.gtk_enable_animations

    def _frame(self, _widget, clock) -> bool:
        anim = self._anim
        if anim is None:
            return GLib.SOURCE_REMOVE
        now = clock.get_frame_time()
        if not anim["start"]:
            anim["start"] = now
        self.queue_draw()
        if (now - anim["start"]) / 1000.0 < anim["length"]:
            return GLib.SOURCE_CONTINUE
        self._anim = None
        self._tick = 0
        self._settle()
        return GLib.SOURCE_REMOVE

    def _stop(self) -> None:
        if self._tick:
            self.remove_tick_callback(self._tick)
            self._tick = 0
        self._anim = None

    def _settle(self) -> bool:
        self.emit("settled")
        return GLib.SOURCE_REMOVE

    @property
    def busy(self) -> bool:
        return self._anim is not None

    # --- drawing ---------------------------------------------------------

    def _draw(self, _area, cr, width: int, height: int) -> None:
        game = self._game
        if game is None:
            return
        tile = self._tile_for(width)
        board_w = LENGTH * tile + (LENGTH - 1) * GAP
        board_h = GUESSES * tile + (GUESSES - 1) * GAP
        ox, oy = (width - board_w) / 2, (height - board_h) / 2

        anim = self._anim
        elapsed = 0.0
        if anim is not None:
            clock = self.get_frame_clock()
            if clock is not None and anim["start"]:
                elapsed = (clock.get_frame_time() - anim["start"]) / 1000.0

        cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(tile * LETTER)

        shake = 0.0
        if anim is not None and anim["kind"] == "shake":
            share = min(elapsed / SHAKE_MS, 1.0)
            shake = math.sin(share * math.tau * 2.5) * SHAKE_SWING * (1 - share)

        for row in range(GUESSES):
            for column in range(LENGTH):
                x = ox + column * (tile + GAP)
                y = oy + row * (tile + GAP)
                letter, mark, filled = self._face(game, row, column)
                squash = 1.0
                if anim is not None and anim["row"] == row:
                    if anim["kind"] == "shake":
                        x += shake
                    else:
                        squash, filled, mark = self._flip(
                            elapsed, column, letter, mark, filled
                        )
                self._tile(cr, x, y, tile, letter, mark, filled, squash)

    def _face(self, game: Game, row: int, column: int):
        """What is on a given tile: its letter, its mark, and whether it is
        filled in -- which is the same question as whether it has been
        submitted."""
        if row < len(game.guesses):
            guess = game.guesses[row]
            return guess.word[column], guess.marks[column], True
        if row == len(game.guesses) and column < len(self._typed):
            return self._typed[column], ABSENT, False
        return "", ABSENT, False

    def _flip(self, elapsed: float, column: int, letter: str, mark: int, filled: bool):
        """A tile part-way through turning over.

        Edge on at the halfway point, which is where it changes sides -- the
        same thing a hand does with a card, and the reason the colour arriving
        does not need announcing. Before halfway it is still showing the letter
        as it was typed.
        """
        share = (elapsed - STAGGER_MS * column) / FLIP_MS
        if share <= 0:
            return 1.0, False, ABSENT
        if share >= 1:
            return 1.0, filled, mark
        squash = max(abs(math.cos(math.pi * share)), 0.04)
        if share < 0.5:
            return squash, False, ABSENT
        return squash, filled, mark

    def _tile(
        self,
        cr,
        x: float,
        y: float,
        size: float,
        letter: str,
        mark: int,
        filled: bool,
        squash: float,
    ) -> None:
        cr.save()
        cr.translate(x + size / 2, y + size / 2)
        cr.scale(1.0, squash)
        cr.translate(-size / 2, -size / 2)
        radius = size * ROUND

        if filled:
            name = {CORRECT: "correct", PRESENT: "present", ABSENT: "absent"}[mark]
            cr.set_source_rgb(*self._ink[name])
            _rounded(cr, 0, 0, size, size, radius)
            cr.fill()
            ink = self._ink[f"on_{name}"]
        else:
            cr.set_source_rgb(*self._ink["typed" if letter else "edge"])
            cr.set_line_width(2.0)
            _rounded(cr, 1, 1, size - 2, size - 2, radius)
            cr.stroke()
            ink = self._ink["ink"]

        if letter:
            cr.set_source_rgb(*ink)
            extents = cr.text_extents(letter)
            cr.move_to(
                (size - extents.width) / 2 - extents.x_bearing,
                (size - extents.height) / 2 - extents.y_bearing,
            )
            cr.show_text(letter)

        if filled and mark != ABSENT:
            # A fresh path first. `show_text` leaves a current point behind, and
            # `arc` joins the current point to the start of the arc -- which
            # drew every ring on the board with a little tail running back to
            # the letter, visible in the first screenshots and in nothing else.
            cr.new_path()
            # The shape that says which colour this is without being the colour.
            # A filled dot for a letter in its place, an open ring for one that
            # is in the word somewhere else, and nothing for one that is not.
            cr.set_source_rgb(*ink)
            spot = size * MARK
            # The bottom-right corner, not the top-right. These are capitals:
            # nothing descends, so the bottom corners are the two places on a
            # tile where a mark is never on top of a letter -- which is what the
            # first cut of this drew, with a ring through the shoulder of every
            # C and A on the board.
            cx, cy = size - spot * 1.7, size - spot * 1.7
            if mark == CORRECT:
                cr.arc(cx, cy, spot, 0, math.tau)
                cr.fill()
            else:
                cr.set_line_width(max(size * 0.035, 1.5))
                cr.arc(cx, cy, spot * 0.82, 0, math.tau)
                cr.stroke()
        cr.restore()


class Keyboard(Gtk.Grid):
    """Twenty-eight buttons on a twenty-column grid.

    Twenty columns because the rows do not divide evenly: ten keys on the first,
    nine indented by half a key on the second, and seven between an enter and a
    backspace worth a key and a half each. Two grid columns to a letter makes
    every one of those a whole number, which is the only way three rows of
    different shapes line up without a pile of spacers.
    """

    __gtype_name__ = "FiveLettersKeyboard"

    __gsignals__: ClassVar[dict] = {
        "letter": (GObject.SignalFlags.RUN_FIRST, None, (str,)),
        "enter": (GObject.SignalFlags.RUN_FIRST, None, ()),
        "back": (GObject.SignalFlags.RUN_FIRST, None, ()),
    }

    def __init__(self) -> None:
        super().__init__()
        self.set_column_homogeneous(True)
        self.set_row_spacing(6)
        self.set_column_spacing(4)
        self.set_margin_start(4)
        self.set_margin_end(4)
        self._keys: dict[str, Gtk.Button] = {}

        for row, letters in enumerate(KEYBOARD):
            span = 2
            start = (20 - len(letters) * span) // 2
            if row == len(KEYBOARD) - 1:
                start = 3
                enter = self._button("ENTER", wide=True)
                enter.connect("clicked", lambda *_: self.emit("enter"))
                self.attach(enter, 0, row, 3, 1)
                back = self._button("DELETE", wide=True)
                back.connect("clicked", lambda *_: self.emit("back"))
                self.attach(back, 17, row, 3, 1)
            for index, letter in enumerate(letters):
                button = self._button(letter)
                button.connect("clicked", self._on_letter, letter)
                self.attach(button, start + index * span, row, span, 1)
                self._keys[letter] = button

    def _button(self, label: str, *, wide: bool = False) -> Gtk.Button:
        button = Gtk.Button(label=label)
        button.add_css_class("key")
        if wide:
            button.add_css_class("wide")
        button.set_can_focus(False)
        return button

    def _on_letter(self, _button, letter: str) -> None:
        self.emit("letter", letter)

    def refresh(self, states: dict[str, int]) -> None:
        """Colour each key by the best thing known about its letter."""
        names = {CORRECT: "correct", PRESENT: "present", ABSENT: "absent"}
        for letter, button in self._keys.items():
            for name in names.values():
                button.remove_css_class(name)
            mark = states.get(letter)
            if mark is not None:
                button.add_css_class(names[mark])
