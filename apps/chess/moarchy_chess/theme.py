"""The colours of a board.

The half that reads the phone's palette lives in `moarchy_ui.theme` and is the
same in every app here. This is the half that is Chess's own: two squares, two
sets of men, and the marks drawn on top of them.

A chessboard is one hue in two strengths, which is a different problem from
Reversi's felt. Reversi mixes the theme's green into the background and stops;
here the *same* hue has to produce a pair that stay clearly apart from each
other and from both sets of pieces, under a near-black theme and a near-white
one. So the dark square is the hue laid into the window's background and the
light square is the hue laid into the window's foreground, which makes the pair
move together when the theme flips and keeps their distance while they do.

The hue is brown, and that is a small piece of conservatism: green and buff is a
real tournament board, but brown and cream is the one anybody recognises at
43px, and the point of the theme is that the board still says chess after it.

The men stay dark and light rather than becoming two of the theme's hues, and
that is a deliberate refusal, for the reasons Reversi's discs record: two hues
is exactly the kind of theming that looks good in a screenshot and fails in
daylight, for the eight percent of men who cannot tell the popular pair apart,
and on a 43px square. Dark against light survives all three -- so the pieces
take a tint from the theme and keep their contrast.

Everything here returns a solid colour rather than something translucent. The
board is drawn every frame of every move, and blending a layer per piece per
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

# How much of the theme's brown survives into each square. The dark square is
# mixed into the window's background and the light one into its foreground, so
# a dark theme and a light one each get a board that belongs to them -- and the
# two amounts differ because a pale wash of brown on a light theme reads as a
# mistake, while the same wash on a dark one is the only thing keeping the board
# off the window.
DARK_SQUARE_ON_DARK = 0.44
DARK_SQUARE_ON_LIGHT = 0.78
LIGHT_SQUARE_ON_DARK = 0.42
LIGHT_SQUARE_ON_LIGHT = 0.34


@dataclass(frozen=True)
class Board:
    """Every colour the board is drawn with, resolved from the theme once."""

    light: str
    dark: str
    line: str
    white: str
    white_rim: str
    black: str
    black_rim: str
    accent: str
    check: str


def board_colours(p: Palette) -> Board:
    """The board, the men and the marks, from the phone's palette.

    Both squares are the same hue laid over the palest colour the theme has --
    its foreground on a dark theme, its background on a light one -- at two
    different strengths. Mixing the dark square into the *window* instead was
    the first attempt and it inverts on a light theme: the foreground is then
    the dark end, so the light square comes out darker than the dark one and the
    board reads as a photographic negative of itself.
    """
    hue = hue_of(p, "brown")
    pale = p.foreground if p.dark else p.background
    dark = mix(
        hue,
        p.background,
        DARK_SQUARE_ON_DARK if p.dark else DARK_SQUARE_ON_LIGHT,
    )
    light = mix(hue, pale, LIGHT_SQUARE_ON_DARK if p.dark else LIGHT_SQUARE_ON_LIGHT)
    # Nearly white and nearly black, tinted by the theme rather than taken from
    # it. Eight per cent is enough for the men to belong to the phone and not
    # enough to cost them the contrast they exist for.
    white = mix(p.foreground, "#f7f6f4", 0.08)
    black = mix(p.background, "#101014", 0.18)
    return Board(
        light=light,
        dark=dark,
        # A shade of the dark square rather than a shade of the window: the
        # frame has to stay darker than the board in both directions, and
        # deriving it from the background makes it lighter than the board on a
        # light theme.
        line=mix(dark, "#000000", 0.66),
        white=white,
        white_rim=mix("#000000", white, 0.45),
        black=black,
        black_rim=mix("#ffffff", black, 0.32),
        accent=p.accent,
        check=hue_of(p, "red"),
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
/* Whose turn it is, said on the name line rather than only in the status text:
   at arm's length on a bus the ring is read and the sentence is not. */
.side {{
  padding: 4px 8px;
  border-radius: 12px;
  border: 2px solid transparent;
}}
.side.playing {{
  border-color: {p.accent};
  background: {mix(p.accent, p.background, 0.12)};
}}
.who {{
  font-size: 0.78rem;
  font-weight: 700;
  letter-spacing: 0.05em;
}}
.edge {{
  font-size: 0.74rem;
  font-weight: 700;
  font-feature-settings: "tnum";
  color: {p.accent};
}}
.status {{
  font-size: 0.95rem;
  color: @moarchy_dim;
}}
.status.alert {{
  color: {p.accent};
  font-weight: 600;
}}
.status.check {{
  color: {board.check};
  font-weight: 700;
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
.promotion button {{
  padding: 6px;
  border-radius: 14px;
}}
"""
    )
