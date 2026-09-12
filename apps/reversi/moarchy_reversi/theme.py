"""The colours of a board.

The half that reads the phone's palette lives in `moarchy_ui.theme` and is the
same in every app here. This is the half that is Reversi's own: a felt, a pair
of discs and the marks drawn on top of them.

The discs stay dark and light rather than becoming two of the theme's hues, and
that is a deliberate refusal. Two hues is exactly the kind of theming that looks
good in a screenshot and fails in daylight, for the eight percent of men who
cannot tell the popular pair apart, and on a 43px square. Dark against light is
the one distinction that survives all three -- so the discs take a *tint* from
the theme and keep their contrast, while the board underneath them is the
theme's own green and changes completely when the phone's theme does.

Everything here returns a solid colour rather than something translucent. The
board is drawn every frame of every flip, and blending a layer per disc per
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

# How much of the theme's green survives into the felt. A dark theme wants the
# board darker than the hue itself or the discs have nothing to sit against; a
# light one wants more of it, because a pale wash of green reads as a mistake.
FELT_DARK = 0.34
FELT_LIGHT = 0.58


@dataclass(frozen=True)
class Board:
    """Every colour the board is drawn with, resolved from the theme once."""

    felt: str
    line: str
    dark: str
    dark_rim: str
    light: str
    light_rim: str
    accent: str


def board_colours(p: Palette) -> Board:
    felt = mix(hue_of(p, "green"), p.background, FELT_DARK if p.dark else FELT_LIGHT)
    # A shade of the felt rather than a shade of the window: grid lines have to
    # stay darker than the board in both directions, and deriving them from the
    # background makes them lighter than it on a light theme.
    line = mix(felt, "#000000", 0.70)
    dark = mix(p.background, "#0d0d10", 0.22)
    light = mix(p.foreground, "#f4f3f1", 0.14)
    return Board(
        felt=felt,
        line=line,
        dark=dark,
        dark_rim=mix("#ffffff", dark, 0.20),
        light=light,
        light_rim=mix("#000000", light, 0.14),
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
/* The two chips over the board. Same two colours the discs are drawn with, so
   "you are dark" is answered by looking rather than by reading. */
.chip {{
  min-width: 22px;
  min-height: 22px;
  border-radius: 11px;
}}
.chip.dark {{ background: {board.dark}; border: 1px solid {board.dark_rim}; }}
.chip.light {{ background: {board.light}; border: 1px solid {board.light_rim}; }}

/* Whose turn it is, said on the score line rather than only in the status
   text: at arm's length on a bus the ring is read and the sentence is not. */
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
.status {{
  font-size: 0.95rem;
  color: @moarchy_dim;
}}
.status.alert {{
  color: {p.accent};
  font-weight: 600;
}}
.thinking {{ min-height: 3px; }}
.thinking > trough,
.thinking > trough > progress {{ min-height: 3px; border-radius: 2px; }}

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
.result {{
  font-size: 1.35rem;
  font-weight: 700;
}}
"""
    )
