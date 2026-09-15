"""The colours of a countdown.

The half that reads the phone's theme is `moarchy_ui.theme` and is the same in
every app here. This is the half that is Launches' own, and it is two
decisions.

**The badge is a disc of the status's own colour with a short mark in it.**
Not the rocket's photograph: twenty JPEGs is twenty requests to a CDN on a
metered connection, each one telling that CDN which launches somebody
watches, for pictures this screen has no room for. Go is green, Hold is
yellow, Failure is red; the letters in the disc are what still works for
somebody who cannot tell those apart.

**The disc is tinted, the digits are the theme's own foreground.** A solid
hue with light text on it is unreadable on a yellow Hold in a light theme,
and a hue on a hue is unreadable in half the palettes people actually run.
A wash of the colour under the theme's ordinary text colour is legible in
every theme this can be handed, which is the property that matters more
than the colour being strong.
"""

from __future__ import annotations

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

SOON = "green"
LATE = "red"
STAR = "yellow"
WAIT = "yellow"

BADGE_HUES = ("blue", "cyan", "magenta", "orange", "green", "yellow", "brown", "red")
BADGE_TINT = 0.28
TARGET = 44
BADGE = 36
MARGIN = 12


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

.launch-row {{
  padding: 8px {MARGIN}px;
  border-bottom: 1px solid @moarchy_line;
}}
.launch-row:last-child {{ border-bottom: none; }}

.badge {{
  min-width: {BADGE}px;
  min-height: {BADGE}px;
  border-radius: {BADGE // 2}px;
  font-size: 0.72rem;
  font-weight: 700;
  font-feature-settings: "tnum";
}}

.launch-name {{ font-weight: 600; }}

.launch-note {{
  font-size: 0.78rem;
  color: @moarchy_dim;
  font-feature-settings: "tnum";
}}
.launch-when {{
  font-weight: 600;
  font-feature-settings: "tnum";
}}
.soon {{ color: {hue_of(p, SOON)}; }}
.late {{ color: {hue_of(p, LATE)}; }}
.wait {{ color: {hue_of(p, WAIT)}; }}
.dim {{ color: @moarchy_dim; }}

/* --- the star ------------------------------------------------------------- */

.star {{ color: @moarchy_dim; }}
.star.on {{ color: {hue_of(p, STAR)}; }}
.star:checked {{ background-color: transparent; }}

/* --- chrome --------------------------------------------------------------- */

.tabbar {{ border-top: 1px solid @moarchy_line; }}

.detail {{
  padding: {MARGIN}px;
}}
.detail-name {{
  font-size: 1.15rem;
  font-weight: 700;
}}
.detail-when {{
  font-size: 1.35rem;
  font-weight: 700;
  font-feature-settings: "tnum";
  margin-top: 4px;
  margin-bottom: 8px;
}}
.fact-row {{
  padding: 6px 0;
  border-bottom: 1px solid @moarchy_line;
}}
.fact-label {{
  font-size: 0.78rem;
  color: @moarchy_dim;
}}
.fact-value {{
  font-weight: 600;
}}
.detail-body {{
  margin-top: 12px;
}}
"""
    )
