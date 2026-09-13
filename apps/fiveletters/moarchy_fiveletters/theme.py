"""The colours of thirty tiles and twenty-eight keys.

The half that reads the phone's palette lives in `moarchy_ui.theme`. This is the
half that is this game's own, and it is the one app here where **the colours are
the rules**: green means the letter is in that place, yellow means it is in the
word somewhere else, grey means it is not in the word. There is nothing else on
the tile saying so.

That is exactly the thing Reversi refuses to do with its discs, and the reason
it is allowed here is that this game has never pretended otherwise -- every
version of it anybody has played works this way, and a person who cannot
separate green from yellow is not going to be helped by a fourth colour. What
this app does instead is what the tile can carry without becoming a different
game: **a mark of its own on every tile**, a filled circle for a letter in the
right place and an open ring for one in the wrong place, drawn small in the
corner. A tile then says which of the three it is by shape as well as by hue,
which costs one arc per tile and is the difference between a playable board and
an unplayable one for about one man in twelve.

The green and the yellow are the theme's own, not the newspaper's. On a theme
whose green and yellow are close together they are pulled apart -- see
`board_colours` -- because the two of them sitting next to each other is the
whole of what this screen is.
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

# How far the tile colours are pushed towards the window, so that white letters
# on them stay readable on a light theme and the board does not glow on a dark
# one.
SOLID_DARK = 0.86
SOLID_LIGHT = 0.92

# An empty tile's outline, and a tile with a letter typed but not yet submitted.
EDGE = 0.20
TYPED = 0.42


@dataclass(frozen=True)
class Board:
    """Every colour the board and the keyboard are drawn with."""

    correct: str
    present: str
    absent: str
    ink: str
    edge: str
    typed: str
    on_correct: str
    on_present: str
    on_absent: str
    key: str
    key_text: str


def _rgb(colour: str) -> tuple[int, int, int]:
    text = colour.lstrip("#")
    if len(text) == 3:
        text = "".join(c * 2 for c in text)
    return int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16)


def _light(colour: str) -> float:
    """How bright a colour is, on the crude weighting that has been good enough
    for choosing black-or-white text since the nineteen-fifties."""
    red, green, blue = _rgb(colour)
    return (red * 299 + green * 587 + blue * 114) / 255000.0


def _on(colour: str, p: Palette) -> str:
    """Which of the theme's two extremes to write on this tile.

    Not always the background, which is what the first cut of this file did: on
    a light theme that is white, and white on the theme's yellow is a tile
    nobody can read. Whichever of the foreground and the background is further
    from the tile wins, which on any theme is the right answer and on a strange
    one is at least the better of two.
    """
    tile = _light(colour)
    return (
        p.background
        if abs(_light(p.background) - tile) > abs(_light(p.foreground) - tile)
        else p.foreground
    )


def _apart(first: str, second: str) -> bool:
    """Are these two far enough apart to be told apart at a glance?

    A plain sum of channel differences, which is crude and is the right kind of
    crude: the question is not whether two colours are perceptually distinct by
    some model, it is whether a theme has shipped a green and a yellow that are
    nearly the same colour -- and that shows up as a small number here.
    """
    return sum(abs(a - b) for a, b in zip(_rgb(first), _rgb(second), strict=False)) > 90


def board_colours(p: Palette) -> Board:
    solid = SOLID_DARK if p.dark else SOLID_LIGHT
    correct = mix(hue_of(p, "green"), p.background, solid)
    present = mix(hue_of(p, "yellow"), p.background, solid)
    if not _apart(correct, present):
        # This theme's green and yellow are too close to use side by side, and
        # side by side is the only way this game ever uses them. The yellow
        # moves to orange, which every theme also names and which no theme has
        # ever put next to its green.
        present = mix(hue_of(p, "orange"), p.background, solid)
    return Board(
        correct=correct,
        present=present,
        # The absent colour is not a hue. It is the one state that means "stop
        # thinking about this letter", and a grey is what that looks like.
        absent=mix(p.foreground, p.background, 0.34),
        ink=p.foreground,
        edge=mix(p.foreground, p.background, EDGE),
        typed=mix(p.foreground, p.background, TYPED),
        on_correct=_on(correct, p),
        on_present=_on(present, p),
        on_absent=_on(mix(p.foreground, p.background, 0.34), p),
        key=mix(p.foreground, p.background, 0.16),
        key_text=p.foreground,
    )


def rgb(colour: str) -> tuple[float, float, float]:
    """A hex colour as cairo wants it: three floats."""
    red, green, blue = _rgb(colour)
    return red / 255.0, green / 255.0, blue / 255.0


def stylesheet(p: Palette) -> str:
    board = board_colours(p)
    return (
        palette_css(p)
        + f"""
/* The keyboard. Twenty-eight buttons, styled rather than drawn, because a key
   is a thing that has to look pressed -- and GTK already knows how to do that
   on a touch screen better than a draw function would. */
.key {{
  font-size: 1.0rem;
  font-weight: 700;
  min-height: 46px;
  min-width: 0;
  padding: 0;
  border-radius: 6px;
  background: {board.key};
  color: {board.key_text};
  border: none;
  box-shadow: none;
}}
.key:hover {{ background: {mix(p.foreground, p.background, 0.26)}; }}
.key.wide {{ font-size: 0.72rem; letter-spacing: 0.04em; }}
.key.correct {{ background: {board.correct}; color: {board.on_correct}; }}
.key.present {{ background: {board.present}; color: {board.on_present}; }}
.key.absent {{
  background: {mix(p.foreground, p.background, 0.30)};
  color: {mix(p.foreground, p.background, 0.55)};
}}

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
/* One bar of the guess distribution: a number on a coloured strip, as wide as
   its share of the days. The label sits inside the bar when it fits and beside
   it when it does not, which is what `.bar.empty` is for. */
.bar {{
  background: {board.correct};
  color: {board.on_correct};
  border-radius: 4px;
  padding: 2px 8px;
  font-feature-settings: "tnum";
  font-weight: 700;
}}
.bar.empty {{
  background: {mix(p.foreground, p.background, 0.14)};
  color: @moarchy_dim;
}}
.bar-label {{
  font-feature-settings: "tnum";
  color: @moarchy_dim;
  min-width: 14px;
}}
.actionbar {{
  padding: 8px 12px 12px 12px;
  border-top: 1px solid @moarchy_line;
}}
"""
    )
