"""The colours of a sheet of paper with a hash drawn on it.

The half that reads the phone's palette lives in `moarchy_ui.theme` and is the
same in every app here. This is the half that is this game's own: a sheet, four
pencil rules, and two marks drawn on them.

The two marks take two of the theme's hues, which is exactly what Reversi
refuses to do -- and the difference is the shapes. Reversi's discs are one
circle and another circle, so colour is the only thing telling them apart, and
the popular pair fails for the eight percent of men who cannot separate red from
green. An X is not an O at any size, in any light, to anybody. The colour here
is decoration on top of a distinction the shape has already made, so it can
follow the theme without carrying any of the reading.

It is blue and red rather than red and green even so, because a hue that fails
is still a hue that fails, and this pair costs nothing to keep.

The grid is a hash and not a box: four rules that overshoot their crossings,
the way a pencil does, with no border around the outside. A bordered three by
three is a chessboard with the squares left out; the hash is what makes somebody
recognise this game from across a room without reading a word of the screen.

Everything here returns a solid colour rather than something translucent. A mark
is drawn every frame of the two hundred milliseconds it takes to arrive, and
blending a layer per frame is not free on a Mali-400 with no GL.
"""

from __future__ import annotations

from dataclasses import dataclass

from moarchy_ui.theme import (  # noqa: F401  -- re-exported for the app
    COLORS,
    CURRENT_THEME,
    GNOME,
    Palette,
    fallback,
    hue_of,
    load,
    mix,
    palette_css,
)

# How far the sheet stands off the window, and in which direction. A dark theme
# wants the paper lifted towards its own raised surface; a light one wants it
# *sunk*, because a white card on an off-white window is a card with no edges --
# which is what this looked like before somebody photographed it.
SHEET_DARK = 0.80
SHEET_LIGHT = 0.05

# How much darker than the paper a rule is drawn. The pencil has to stay under
# the marks: four rules at the weight of an X turn the hash into the subject of
# the picture and the game into decoration on top of it.
RULE_INK = 0.30

# What is left of a mark that is not part of the winning line. Not zero: the
# board still has to be readable as the game that was played, and a move that
# vanishes when somebody wins is a move nobody gets to look at.
FADED = 0.34


@dataclass(frozen=True)
class Board:
    """Every colour the board is drawn with, resolved from the theme once."""

    sheet: str
    rule: str
    x: str
    o: str
    faded_x: str
    faded_o: str
    accent: str


def board_colours(p: Palette) -> Board:
    if p.dark:
        sheet = mix(p.surface, p.background, SHEET_DARK)
        pencil = "#ffffff"
    else:
        sheet = mix(p.foreground, p.background, SHEET_LIGHT)
        pencil = "#000000"
    x = hue_of(p, "blue")
    o = hue_of(p, "red")
    return Board(
        sheet=sheet,
        # Ink mixed *into* the sheet rather than the sheet mixed into ink, which
        # is the same function with its arguments the other way round and was
        # the difference between a grey pencil line and a black bar.
        rule=mix(pencil, sheet, RULE_INK),
        x=x,
        o=o,
        faded_x=mix(x, sheet, FADED),
        faded_o=mix(o, sheet, FADED),
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
/* The mark on a score chip, in the same colour the board draws it. "You are X"
   is then answered by looking rather than by reading, which at arm's length on
   a bus is the difference between answered and not. */
.glyph {{
  font-size: 1.1rem;
  font-weight: 800;
}}
.glyph.x {{ color: {board.x}; }}
.glyph.o {{ color: {board.o}; }}

/* Whose turn it is, said on the score line rather than only in the status. */
.side {{
  padding: 5px 10px;
  border-radius: 14px;
  border: 2px solid transparent;
}}
.side.playing {{
  border-color: {p.accent};
  background: {mix(p.accent, p.background, 0.12)};
}}
.count {{
  font-size: 1.25rem;
  font-weight: 700;
  font-feature-settings: "tnum";
}}
.who {{
  font-size: 0.72rem;
  letter-spacing: 0.06em;
  color: @moarchy_dim;
}}
.drawn {{
  font-size: 0.72rem;
  letter-spacing: 0.06em;
  color: @moarchy_dim;
}}
.status {{
  font-size: 0.95rem;
  color: @moarchy_dim;
}}
.status.alert {{
  color: {p.accent};
  font-weight: 600;
}}

/* The bottom bar. Every control the game itself needs is down here, where a
   thumb is, rather than in the header a hand has to be re-gripped to reach. */
.actionbar {{
  padding: 8px 12px 12px 12px;
  border-top: 1px solid @moarchy_line;
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
