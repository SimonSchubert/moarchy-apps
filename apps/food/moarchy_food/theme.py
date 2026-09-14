"""The colours of a Nutri-Score.

The half that reads the phone's theme is `moarchy_ui.theme` and is the same
in every app here. This is the half that is Food's own, and it is one
decision: the five letters of a Nutri-Score (and of an Eco-Score) are the
theme's own green through red, not the official traffic-light palette.

The official colours are a brand. They also fail the same test Five Letters
makes of its tiles: roughly one man in twelve cannot tell this green from
this red, so every badge carries the letter as well as the hue, and the
letter is the answer. The colour is what makes three badges scannable from
the other end of a shopping aisle.
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

# Nutri-Score A is the theme's green, E is its red, and the three between
# them walk the hues a theme already names. Official Nutri-Score yellow is
# a colour this phone does not have; the theme's yellow is the one that
# will still be yellow after `omarchy-theme-set`.
GRADE_HUES = {
    "a": "green",
    "b": "cyan",
    "c": "yellow",
    "d": "orange",
    "e": "red",
}

# How much of the hue goes into the badge. Solid enough to tell five of
# them apart at arm's length, pale enough that the theme's own text colour
# reads on top of it in both a light theme and a dark one -- the same
# argument Coins makes of its rank discs.
# Coins' rank discs: a wash of the hue under the theme's own text colour,
# so the letter reads in every theme rather than white-on-yellow vanishing
# on a light one.
GRADE_TINT = 0.62

TARGET = 44
MARGIN = 12
BADGE = 48


def stylesheet(p: Palette) -> str:
    rules = []
    for letter, role in GRADE_HUES.items():
        hue = hue_of(p, role)
        tint = mix(hue, p.background, GRADE_TINT)
        rules.append(
            f".grade-{letter} {{ background-color: {tint}; color: {p.foreground}; }}"
        )
    return (
        palette_css(p)
        + "\n".join(rules)
        + f"""
/* --- scanner -------------------------------------------------------------- */

.scan {{ background-color: {p.background}; }}
.scan-preview {{ background-color: #111111; }}

/* Four corners rather than a box: a box over a barcode is a box over the
   thing the decoder has to see. The corners sit outside the quiet zone. */
.reticle {{
  min-width: 240px;
  min-height: 140px;
  border: 2px solid {p.foreground};
  border-radius: 12px;
  opacity: 0.85;
  background-color: transparent;
}}

.scan-hint {{
  font-size: 0.92rem;
  font-weight: 600;
  color: {p.foreground};
  background-color: {mix(p.background, "#000000" if p.dark else p.foreground, 0.72)};
  padding: 8px 14px;
  border-radius: 999px;
}}

/* --- a product ------------------------------------------------------------ */

.product {{ padding: {MARGIN}px; }}

.product-name {{
  font-size: 1.2rem;
  font-weight: 700;
}}
.product-note {{
  font-size: 0.88rem;
  color: @moarchy_dim;
}}

.hero {{
  min-height: 140px;
  border-radius: 12px;
  background-color: {p.surface};
}}

.letter {{
  min-width: {BADGE}px;
  min-height: {BADGE}px;
  border-radius: 12px;
  font-size: 1.4rem;
  font-weight: 800;
  background-color: {p.surface};
}}
.letter-caption {{
  font-size: 0.72rem;
  color: @moarchy_dim;
}}

.nutrient-row {{
  padding: 8px 0;
  border-bottom: 1px solid @moarchy_line;
}}
.nutrient-row:last-child {{ border-bottom: none; }}
.nutrient-label {{ color: @moarchy_dim; }}
.nutrient-value {{
  font-weight: 600;
  font-feature-settings: "tnum";
}}

.allergens {{
  font-weight: 600;
  color: {hue_of(p, "red")};
}}

.ingredients {{
  font-size: 0.88rem;
  color: @moarchy_dim;
}}

/* --- history -------------------------------------------------------------- */

.food-row {{
  padding: 8px {MARGIN}px;
  border-bottom: 1px solid @moarchy_line;
}}
.food-row:last-child {{ border-bottom: none; }}
.food-name {{ font-weight: 600; }}
.food-note {{
  font-size: 0.78rem;
  color: @moarchy_dim;
}}

.tabbar {{ border-top: 1px solid @moarchy_line; }}
"""
    )
