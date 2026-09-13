"""The colours of a minefield.

The half that reads the phone's palette lives in `moarchy_ui.theme` and is the
same in every app here. This is the half that is Minesweeper's own: a covered
cell, an opened one, and the eight numbers drawn on them.

**Eight numbers and eight hues.** That is not a coincidence being taken
advantage of, it is the reason this app can be themed at all: every Omarchy
theme names red, orange, yellow, green, cyan, blue, magenta and brown, and this
game has exactly eight numbers to colour. The classic Windows palette -- 1 blue,
2 green, 3 red, 4 navy, 5 maroon, 6 teal -- maps onto six of them almost
exactly, and the two nobody remembers take the last two.

The numbers are the one thing in this app carrying information in colour alone,
and that is not a choice: a 3 is legible as a 3. The colour is there so that a
board reads as a *shape* -- so that the wall of 1s along an edge is one thing
and the 3 in the middle of it is another -- and nothing is lost by not seeing
it, which is the test Reversi's discs fail and these pass.

Everything here returns a solid colour rather than something translucent. A
flood opens a hundred and fifty cells in one frame, and blending a layer per
cell is not free on a Mali-400 with no GL.
"""

from __future__ import annotations

from dataclasses import dataclass

from moarchy_ui.theme import (  # noqa: F401  -- re-exported for the app
    COLORS,
    CURRENT_THEME,
    GNOME,
    HUES,
    Palette,
    fallback,
    hue_of,
    load,
    mix,
    palette_css,
)

# How far a covered cell stands off the window, and how far an opened one sinks
# into it. Both are mixes of the theme's *foreground* into its background rather
# than of its surface, and that is the fix for the first version of this file: a
# card colour is nearly the window colour on a light theme, so the covered cells
# came out invisible and the board photographed as a scatter of numbers on
# nothing. Foreground into background moves in the right direction on both
# themes by construction -- darker on a light one, lighter on a dark one.
#
# The gap between the two is the whole readability of the board. A covered cell
# is a thing you can press; an opened one is a hole where a thing used to be,
# and should be very close to the window it sits in.
LID = 0.17
PIT = 0.05

# The classic six, in the order the numbers run, then two more for the 7 and the
# 8 -- which almost nobody has seen on a board and which still have to be
# distinguishable from everything above them.
NUMBER_HUES = (
    "blue",
    "green",
    "red",
    "magenta",
    "brown",
    "cyan",
    "orange",
    "yellow",
)


@dataclass(frozen=True)
class Board:
    """Every colour the field is drawn with, resolved from the theme once."""

    lid: str
    lid_top: str
    pit: str
    grid: str
    numbers: tuple[str, ...]
    flag: str
    pole: str
    mine: str
    boom: str
    wrong: str
    accent: str


def board_colours(p: Palette) -> Board:
    lid = mix(p.foreground, p.background, LID)
    pit = mix(p.foreground, p.background, PIT)
    numbers = tuple(
        # Lifted away from the pit they are drawn on, so that a brown 5 on a
        # dark theme is not a brown 5 on brown.
        mix(hue_of(p, name), p.foreground, 0.78)
        for name in NUMBER_HUES
    )
    return Board(
        lid=lid,
        # One light source, top left. It is what makes a covered cell read as
        # something to press rather than as a lighter square.
        lid_top=mix("#ffffff", lid, 0.16 if p.dark else 0.60),
        pit=pit,
        grid=mix(p.foreground, p.background, 0.14),
        numbers=numbers,
        flag=hue_of(p, "red"),
        pole=p.foreground,
        mine=p.foreground,
        boom=hue_of(p, "red"),
        wrong=hue_of(p, "orange"),
        accent=p.accent,
    )


def rgb(colour: str) -> tuple[float, float, float]:
    """A hex colour as cairo wants it: three floats."""
    text = colour.lstrip("#")
    if len(text) == 3:
        text = "".join(c * 2 for c in text)
    return (
        int(text[0:2], 16) / 255.0,
        int(text[2:4], 16) / 255.0,
        int(text[4:6], 16) / 255.0,
    )


def stylesheet(p: Palette) -> str:
    board = board_colours(p)
    return (
        palette_css(p)
        + f"""
/* The two readings above the board: mines left, and the clock. Tabular figures
   on both, because a clock whose digits change width is a clock that jiggles. */
.reading {{
  font-size: 1.3rem;
  font-weight: 700;
  font-feature-settings: "tnum";
}}
.reading.low {{ color: {board.flag}; }}
.reading-label {{
  font-size: 0.70rem;
  letter-spacing: 0.06em;
  color: @moarchy_dim;
}}
.paused {{ color: @moarchy_dim; }}
.status {{
  font-size: 0.95rem;
  color: @moarchy_dim;
}}
.status.alert {{
  color: {p.accent};
  font-weight: 600;
}}
.actionbar {{
  padding: 8px 12px 12px 12px;
  border-top: 1px solid @moarchy_line;
}}
/* The flag button is a mode rather than an action, so it latches. A toggle that
   looked like the button next to it would be a mode nobody could see they were
   in, and on this board that means a tap that opens a mine. */
.marking {{
  background: {mix(board.flag, p.background, 0.22)};
  color: {board.flag};
  font-weight: 700;
}}
.section-heading {{
  font-size: 0.78rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  color: @moarchy_dim;
}}
.figure {{
  font-size: 1.6rem;
  font-weight: 700;
  font-feature-settings: "tnum";
}}
.figure-label {{
  font-size: 0.74rem;
  letter-spacing: 0.06em;
  color: @moarchy_dim;
}}
.tally {{
  padding: 12px;
  border-radius: 14px;
  background: @moarchy_surface;
}}
"""
    )
