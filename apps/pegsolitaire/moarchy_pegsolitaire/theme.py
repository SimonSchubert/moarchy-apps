"""The colours of a board with holes drilled in it.

The half that reads the phone's palette lives in `moarchy_ui.theme` and is the
same in every app here. This is the half that is peg solitaire's own: a board, a
hole, a peg, and the three rings drawn round them.

Four of the theme's hues are used and each one does a job:

    brown   the board. It is a wooden thing and every theme has a brown
    accent  the pegs, which are the subject and want to be the brightest
    yellow  the ring round the peg you have picked up
    green   the rings round the holes it can reach

That is more of the palette than any other app here spends, and it is spent
because every one of those is a different *kind* of thing rather than a
different instance of the same one. Reversi refuses two hues for its discs
because the discs are a circle and a circle; here a board is not a peg is not a
ring you tapped is not a ring you may tap, and each of the four is also in a
different place and a different shape. Nothing is being told apart by colour
alone, which is the whole of that argument.

Everything here returns a solid colour rather than something translucent. The
board is redrawn on every frame of every hop, and blending a layer per peg per
frame is not free on a Mali-400 with no GL.
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

# How much of the theme's brown survives into the board. A dark theme wants the
# wood dark enough that a lit peg sits on it; a light one wants enough of the
# hue that it is wood rather than beige.
WOOD_DARK = 0.24
WOOD_LIGHT = 0.46


@dataclass(frozen=True)
class Board:
    """Every colour the board is drawn with, resolved from the theme once."""

    wood: str
    rim: str
    hole: str
    hole_rim: str
    peg: str
    peg_rim: str
    peg_top: str
    pick: str
    drop: str
    doomed: str


def board_colours(p: Palette) -> Board:
    wood = mix(hue_of(p, "brown"), p.background, WOOD_DARK if p.dark else WOOD_LIGHT)
    peg = p.accent
    return Board(
        wood=wood,
        rim=mix("#000000", wood, 0.24),
        # A hole is a hole: darker than the board on both themes, because a
        # lighter one reads as a peg somebody has painted the wrong colour.
        hole=mix("#000000", wood, 0.42),
        hole_rim=mix("#ffffff", wood, 0.10),
        peg=peg,
        peg_rim=mix("#000000", peg, 0.30),
        # The one light source in the picture, and what stops thirty-two flat
        # circles reading as thirty-two stickers.
        peg_top=mix("#ffffff", peg, 0.28),
        pick=hue_of(p, "yellow"),
        drop=hue_of(p, "green"),
        doomed=hue_of(p, "red"),
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
    return (
        palette_css(p)
        + f"""
.status {{
  font-size: 0.95rem;
  color: @moarchy_dim;
}}
.status.alert {{
  color: {p.accent};
  font-weight: 600;
}}
.counter {{
  font-size: 1.05rem;
  font-weight: 700;
  font-feature-settings: "tnum";
}}
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
.crown {{
  color: {hue_of(p, "yellow")};
}}
"""
    )
