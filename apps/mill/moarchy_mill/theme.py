"""The colours of a Morris board.

The half that reads the phone's palette lives in `moarchy_ui.theme` and is the
same in every app here. This is the half that is Mill's own: a board, the lines
drawn on it, two sets of men, and the rings that say what a tap can do.

**The men stay white and black**, and that is the same deliberate refusal
Reversi makes about its discs, for the same reason: they are a circle and a
circle, so colour is the only thing telling them apart, and the popular pair
fails for the eight percent of men who cannot separate red from green. Light
against dark is the one distinction that survives daylight, a 34px piece and
everybody's eyes -- so the men take a *tint* from the theme and keep their
contrast, while the board underneath them is the theme's own brown and changes
completely when the phone's theme does.

What does take a hue is the two things that are not pieces: the ring round a
piece you have picked up, and the ring round each place it can go. Those are
shapes in different places doing different jobs, and neither of them is telling
you which side anything belongs to.

Everything here returns a solid colour rather than something translucent. The
board is redrawn on every frame of every slide, and blending a layer per piece
per frame is not free on a Mali-400 with no GL.
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
# wood dark enough that a white piece sits on it; a light one wants enough of
# the hue that it is wood rather than beige.
WOOD_DARK = 0.22
WOOD_LIGHT = 0.40


@dataclass(frozen=True)
class Board:
    """Every colour the board is drawn with, resolved from the theme once."""

    wood: str
    line: str
    spot: str
    white: str
    white_rim: str
    black: str
    black_rim: str
    pick: str
    drop: str
    take: str
    mill: str
    accent: str


def board_colours(p: Palette) -> Board:
    wood = mix(hue_of(p, "brown"), p.background, WOOD_DARK if p.dark else WOOD_LIGHT)
    white = mix(p.foreground, "#f4f3f1", 0.14)
    black = mix(p.background, "#0d0d10", 0.22)
    return Board(
        wood=wood,
        # A shade of the wood rather than a shade of the window: the lines have
        # to stay darker than the board in both directions, and deriving them
        # from the background makes them lighter than it on a light theme.
        line=mix("#000000", wood, 0.42),
        spot=mix("#000000", wood, 0.24),
        white=white,
        white_rim=mix("#000000", white, 0.16),
        black=black,
        black_rim=mix("#ffffff", black, 0.22),
        pick=hue_of(p, "yellow"),
        drop=hue_of(p, "green"),
        # The ring round every enemy piece a mill has earned the right to take.
        take=hue_of(p, "red"),
        # The line drawn through a mill as it closes. The theme's accent, which
        # is the colour this whole family of apps uses for "the thing that just
        # happened".
        mill=p.accent,
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
/* The two chips over the board. Same two colours the men are drawn with, so
   "you are white" is answered by looking rather than by reading. */
.chip {{
  min-width: 22px;
  min-height: 22px;
  border-radius: 11px;
}}
.chip.white {{ background: {board.white}; border: 1px solid {board.white_rim}; }}
.chip.black {{ background: {board.black}; border: 1px solid {board.black_rim}; }}
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
