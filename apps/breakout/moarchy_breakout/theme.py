"""The colours of a wall, a bat and a ball.

The half that reads the phone's palette lives in `moarchy_ui.theme`. This is the
half that is Breakout's own, and it spends more of the palette than any other
app here: **a row of bricks takes a hue each**, in the order every theme names
them, so a wall of eight rows is eight of the theme's colours stacked up. That
is what a Breakout wall has looked like since 1976 and it is the one place in
this repository where using the whole palette at once is the design rather than
a failure to choose.

Nothing is being told apart by colour: a brick is a brick wherever it is, the
rows differ only in what they are worth to look at, and **how many hits a brick
has left is drawn as a shape** -- an inset line inside a brick that still needs
another one. That is the same rule Five Letters follows with its corner marks
and Peg Solitaire with its rings, and it is the reason a person who cannot
separate this theme's green from its cyan loses nothing at all.

The field is darker than the window on every theme, because a ball is a small
bright thing and the only way to see a small bright thing is to put it on
something that is not.
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

# The rows, from the top down. Warm at the top where the bricks are worth most,
# cool at the bottom, which is the order an arcade cabinet used and the order
# the eye reads as "far" to "near".
ROW_HUES = ("red", "orange", "yellow", "green", "cyan", "blue", "magenta", "brown")

# How far the field is sunk below the window.
FIELD_DARK = 0.55
FIELD_LIGHT = 0.10


@dataclass(frozen=True)
class Board:
    """Every colour the field is drawn with, resolved from the theme once."""

    field: str
    edge: str
    rows: tuple[str, ...]
    tough: str
    bat: str
    bat_rim: str
    ball: str
    ball_rim: str
    dim: str


def board_colours(p: Palette) -> Board:
    if p.dark:
        field = mix(p.background, "#000000", FIELD_DARK)
    else:
        field = mix(p.foreground, p.background, FIELD_LIGHT)
    rows = tuple(mix(hue_of(p, name), field, 0.88) for name in ROW_HUES)
    ball = mix("#ffffff", p.foreground, 0.72) if p.dark else p.foreground
    return Board(
        field=field,
        edge=mix(p.foreground, field, 0.22),
        rows=rows,
        # The line inside a brick that has another hit in it. Drawn in the
        # field's own colour, so it reads as a groove rather than as a fourth
        # thing on the screen.
        tough=field,
        bat=p.accent,
        bat_rim=mix("#ffffff", p.accent, 0.30),
        ball=ball,
        ball_rim=mix("#000000", ball, 0.25),
        dim=p.dim,
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
.reading {{
  font-size: 1.2rem;
  font-weight: 700;
  font-feature-settings: "tnum";
}}
.reading-label {{
  font-size: 0.70rem;
  letter-spacing: 0.06em;
  color: @moarchy_dim;
}}
/* The lives, as a row of small circles rather than a number. Three of anything
   is faster to read as three shapes than as a digit, and this is a number a
   person glances at in the middle of a rally. */
.life {{
  min-width: 11px;
  min-height: 11px;
  border-radius: 6px;
  background: {board.bat};
}}
.life.spent {{ background: {mix(p.foreground, p.background, 0.16)}; }}
.status {{
  font-size: 0.95rem;
  color: @moarchy_dim;
}}
.status.alert {{
  color: {p.accent};
  font-weight: 600;
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
.actionbar {{
  padding: 8px 12px 12px 12px;
  border-top: 1px solid @moarchy_line;
}}
"""
    )
