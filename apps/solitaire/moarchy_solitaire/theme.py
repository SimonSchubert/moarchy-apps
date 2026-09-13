"""The colours of a table with cards on it.

The half that reads the phone's palette lives in `moarchy_ui.theme` and is the
same in every app here. This is the half that is Klondike's own: a baize, a card
face, a card back, and the two colours a suit can be.

**The cards stay cards.** The face is very nearly white on every theme and the
black suits are very nearly black, which is the same refusal Reversi makes about
its discs and for a sharper reason: at 46px across, a rank and a pip are five
pixels of ink, and a theme that tinted the face would be spending the only
contrast this app has on decoration. The red suits take the theme's red, because
that is the one colour on a playing card that is already a colour.

What does follow the theme is everything the cards sit on and in: the baize, the
backs, the empty slots, the ring round a card you have picked up and the ring
round everywhere it can go. So `omarchy-theme-set` changes the table while the
game is on it, and the cards on the table stay legible in daylight.

Everything here returns a solid colour rather than something translucent. A
tableau of twenty-eight cards is redrawn on every frame of every move, and
blending a layer per card per frame is not free on a Mali-400 with no GL.
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

# How much of the theme's green survives into the baize, and how much ink goes
# in after it on a light theme. The second number is the one that matters: a
# theme green mixed into a near-white window is mint, and mint is a colour for a
# bathroom rather than for a card table. Darkening it afterwards is what turns
# the same hue into baize.
BAIZE_DARK = 0.16
BAIZE_LIGHT = 0.42
BAIZE_SHADE = 0.14

# How white a card face is. Not pure white on a dark theme -- seven columns of
# #ffffff at midnight is a torch -- and not tinted either, because the ink on it
# is five pixels wide.
FACE_DARK = 0.88
FACE_LIGHT = 0.99


@dataclass(frozen=True)
class Baize:
    """Every colour the table is drawn with, resolved from the theme once."""

    baize: str
    face: str
    edge: str
    ink: str
    blood: str
    back: str
    back_line: str
    slot: str
    slot_ink: str
    pick: str
    drop: str
    dim: str


def board_colours(p: Palette) -> Baize:
    if p.dark:
        baize = mix(hue_of(p, "green"), p.background, BAIZE_DARK)
    else:
        baize = mix(
            "#000000", mix(hue_of(p, "green"), p.background, BAIZE_LIGHT), BAIZE_SHADE
        )
    face = mix("#ffffff", p.background, FACE_DARK if p.dark else FACE_LIGHT)
    back = mix(p.accent, p.background, 0.82)
    return Baize(
        baize=baize,
        face=face,
        # The card's own outline, so that two overlapping white cards are two
        # cards. Without it a column reads as one long white shape with writing
        # down it, which is exactly what it looked like before this line.
        edge=mix("#000000", face, 0.22),
        ink=mix("#000000", face, 0.88),
        blood=mix(hue_of(p, "red"), face, 0.90),
        back=back,
        back_line=mix("#000000", back, 0.22),
        # An empty pile is a hole in the baize rather than a card that is not
        # there: darker than the table on both themes, because a lighter one
        # reads as a face-up card with nothing on it.
        slot=mix("#000000", baize, 0.16),
        slot_ink=mix(p.foreground, baize, 0.28),
        pick=p.accent,
        drop=mix(p.accent, baize, 0.55),
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
  font-feature-settings: "tnum";
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
