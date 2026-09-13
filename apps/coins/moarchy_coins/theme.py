"""The colours of a price.

The half that reads the phone's theme is `moarchy_ui.theme` and is the same in
every app here. This is the half that is Coins' own, and it is three decisions.

**Up is the theme's green and down is its red, and neither is ever alone.**
Roughly one man in twelve cannot tell those two apart, so every figure drawn in
them carries its own sign -- `market.percent` always writes one -- and the
colour is the thing that makes a hundred rows scannable rather than the thing
that says which way the number went. The same argument as Fiveletters' marks.

**The badge is a disc of the coin's own colour with its rank in it.** Not the
coin's logo: a hundred logos is a hundred requests to a CDN on a metered
connection, each one telling that CDN which coins somebody watches, for pictures
that are 24 pixels wide. A hue picked from the coin's id is stable for the life
of the coin, costs nothing, and is enough to find the row you were looking at
without reading it.

**The disc is tinted, the digits are the theme's own foreground.** A solid hue
with light text on it is unreadable on a yellow coin in a light theme, and a hue
on a hue is unreadable in half the palettes people actually run. A wash of the
colour under the theme's ordinary text colour is legible in every theme this can
be handed, which is the property that matters more than the colour being strong.
"""

from __future__ import annotations

import zlib

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

UP = "green"
DOWN = "red"
STAR = "yellow"

# The eight hue roles a theme names, as the eight discs a coin can wear. All of
# them rather than a chosen few: with a hundred rows on the page, the point is
# that two coins next to each other are unlikely to match, and dropping the
# awkward hues would make that likelier rather than the list prettier.
BADGE_HUES = ("blue", "cyan", "magenta", "orange", "green", "yellow", "brown", "red")

# How much of the hue goes into the disc. Solid enough to tell eight of them
# apart at arm's length, pale enough that the theme's own text colour reads on
# top of it in both a light theme and a dark one.
BADGE_TINT = 0.28

# The tap target floor, as everywhere else in this repo: the smallest thing a
# thumb hits reliably.
TARGET = 44

# The disc, and the window's own margin. 36 leaves room for three digits at the
# row's font size, which is as many as a rank in the top hundred ever needs.
BADGE = 36
MARGIN = 12


def badge_hue(coin_id: str) -> str:
    """Which of the eight a coin wears, for the life of the coin.

    crc32 of the id rather than `hash()`, which is salted per process in Python
    and would give a coin a different colour on every launch -- turning the one
    property this is for, "my coin is the blue one", into noise.
    """
    return BADGE_HUES[zlib.crc32(coin_id.encode("utf-8")) % len(BADGE_HUES)]


def badges_css(p: Palette) -> str:
    rules = []
    for role in BADGE_HUES:
        tint = mix(hue_of(p, role), p.background, BADGE_TINT)
        rules.append(f".badge-{role} {{ background-color: {tint}; }}")
    return "\n".join(rules)


def stylesheet(p: Palette) -> str:
    return (
        palette_css(p)
        + badges_css(p)
        + f"""
/* --- a row ---------------------------------------------------------------- */

/* Rows are built by hand rather than from Adw.ActionRow: the price and the day
   have to line up in a column of their own down the right-hand edge, and a
   suffix widget lines up with whatever happens to be above it. */
.coin-row {{
  padding: 6px {MARGIN}px;
  border-bottom: 1px solid @moarchy_line;
}}
.coin-row:last-child {{ border-bottom: none; }}

/* The disc. A label rather than anything drawn, so the rank inside it scales
   with the phone's font size and is read out by a screen reader -- which is the
   rule the whole repo keeps about text and cairo. */
.badge {{
  min-width: {BADGE}px;
  min-height: {BADGE}px;
  border-radius: {BADGE // 2}px;
  font-size: 0.78rem;
  font-weight: 700;
  font-feature-settings: "tnum";
}}

.coin-name {{ font-weight: 600; }}

/* tnum on everything that counts, and that is every figure in this app: without
   it a price ticking from 9 to 10 moves every glyph left of it, and a hundred
   rows of that twitches the whole list once a minute. */
.coin-note {{
  font-size: 0.78rem;
  color: @moarchy_dim;
  font-feature-settings: "tnum";
}}
.coin-price {{
  font-weight: 600;
  font-feature-settings: "tnum";
}}
.coin-change {{
  font-size: 0.82rem;
  font-feature-settings: "tnum";
}}
.up {{ color: {hue_of(p, UP)}; }}
.down {{ color: {hue_of(p, DOWN)}; }}
.flat {{ color: @moarchy_dim; }}

/* --- the star ------------------------------------------------------------- */

/* Flat and dim until it is on, then the theme's yellow. The button is the app's
   one action, so it is the one thing in a row that is a colour rather than a
   shade -- and it is {TARGET}px square wherever it appears. */
.star {{ color: @moarchy_dim; }}
.star.on {{ color: {hue_of(p, STAR)}; }}

/* A checked toggle button draws a filled background, which down a column of
   starred rows is four coloured boxes where the design is four stars. The state
   is already carried twice over -- a hollow star becomes a solid one, and grey
   becomes the theme's yellow -- so the box is a third thing saying it. */
.star:checked {{ background-color: transparent; }}

/* --- chrome --------------------------------------------------------------- */

/* The switcher is at the bottom, where a thumb is, and needs a line above it:
   without one the tabs float over whatever the list scrolled under them. */
.tabbar {{ border-top: 1px solid @moarchy_line; }}

.note {{
  font-size: 0.82rem;
  color: @moarchy_dim;
}}
"""
    )
