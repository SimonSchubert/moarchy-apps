"""The colours of a habit grid.

The half that reads the phone's theme lives in `moarchy_ui.theme` and is the
same in every app here. This is the half that is Habits' own: which hue roles a
habit may be given, and the ramp that turns "how much of today was done" into a
fill.

The ramp matters more here than in a notes app, because a heatmap has to show
*degree*. A day half done and a day fully done must be told apart at a glance on
a 360px screen in daylight, so it is a small number of widely separated steps
rather than a continuous alpha.
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

# The eight a habit may be given, in picker order: a 4x2 grid of 48px targets,
# which is what fits across 360px with room to be tapped. Each names a role in
# the theme rather than a colour.
HABIT_COLOURS: tuple[tuple[str, str], ...] = (
    ("green", "Green"),
    ("cyan", "Teal"),
    ("blue", "Blue"),
    ("magenta", "Violet"),
    ("red", "Red"),
    ("orange", "Orange"),
    ("yellow", "Yellow"),
    ("brown", "Clay"),
)

COLOUR_KEYS = tuple(key for key, _ in HABIT_COLOURS)

# Fractions of the hue carried over the background. Four steps, not a gradient:
# on a Mali-400 in sunlight, "roughly two thirds done" is not a distinction
# anyone reads, and four clearly different marks are. Index 0 is an untouched
# day and is drawn from the outline colour instead.
RAMP_DARK = (0.0, 0.30, 0.55, 0.80, 1.0)
RAMP_LIGHT = (0.0, 0.22, 0.44, 0.68, 0.92)

STEPS = len(RAMP_DARK) - 1

# How long the tick animation runs. Long enough to register, short enough that
# ticking four habits in a row is not four waits. Lives here rather than in
# widgets.py because the keyframes below and the timer that removes the class
# have to agree, and one of them has to own the number.
POP_MS = 320


def mark_colour(palette: Palette, key: str, step: int) -> str:
    """The fill of one mark, at a step from 0 (untouched) to STEPS."""
    ramp = RAMP_DARK if palette.dark else RAMP_LIGHT
    step = max(0, min(step, STEPS))
    if step == 0:
        return mix(palette.foreground, palette.background, 0.10)
    return mix(hue_of(palette, key), palette.background, ramp[step])


def marks_css(p: Palette) -> str:
    """One rule per colour per step, plus the outline of an untouched day.

    Class names rather than inline styles, so a theme change is a single reload
    of the provider: every mark already on screen repaints, and the grids never
    learn that a theme exists.
    """
    rules = [
        f"""
/* Size comes from the class, not from a size request: a min-width in CSS beats
   a size request, so the two grids must each name their own. */
.mark {{
  background: {mark_colour(p, "green", 0)};
}}
.mark.day {{
  min-width: 30px;
  min-height: 30px;
  border-radius: 9px;
}}
.mark.cell {{
  min-width: 15px;
  min-height: 15px;
  border-radius: 4px;
}}
.mark.empty {{
  background: transparent;
  border: 2px solid {mix(p.foreground, p.background, 0.18)};
}}
.mark.cell.empty {{
  border-width: 1px;
}}
.mark.future {{
  background: transparent;
  border: 1px dashed {mix(p.foreground, p.background, 0.12)};
}}
.mark.today {{
  border: 2px solid {p.accent};
}}
/* outline, not border: a filled mark sets `border: none`, and the ring has to
   survive that without the two rules fighting over the same property. */
.mark.selected {{
  outline: 3px solid {p.accent};
  outline-offset: 2px;
}}

/* The tick. A halo that expands and fades, plus a short scale, so a thumb is
   told it landed. box-shadow is the load-bearing half -- it needs no layout
   and cannot push its neighbours around, which a growing widget would. */
@keyframes habit-pop {{
  0%   {{ box-shadow: 0 0 0 0 alpha({p.accent}, 0.55); transform: scale(1); }}
  45%  {{ transform: scale(1.28); }}
  100% {{ box-shadow: 0 0 0 14px alpha({p.accent}, 0); transform: scale(1); }}
}}
.mark.just-done {{
  animation: habit-pop {POP_MS}ms ease-out;
}}

/* Reduced motion is a setting people turn on because motion makes them ill.
   The halo alone still says "that landed" without anything moving. */
@media (prefers-reduced-motion: reduce) {{
  .mark.just-done {{ animation: none; }}
}}
.mark-target {{
  padding: 0;
  min-width: 0;
  min-height: 0;
}}
"""
    ]
    for key, _ in HABIT_COLOURS:
        for step in range(1, STEPS + 1):
            fill = mark_colour(p, key, step)
            # The tick sits on the mark, so it takes the ground's own contrast
            # rather than the window's: a light theme's filled mark is dark.
            ink = p.background if p.dark else "#ffffff"
            rules.append(
                f".mark.{key}.step{step} {{ background: {fill}; "
                f"border: none; color: {ink}; }}"
            )
        rules.append(f".swatch.{key} {{ background: {mark_colour(p, key, STEPS)}; }}")
        rules.append(
            f".habitbar.{key} > trough > progress {{ background-color: {hue_of(p, key)}; }}"
        )
        rules.append(f".hue-{key} {{ color: {hue_of(p, key)}; }}")
    return "\n".join(rules)


def stylesheet(p: Palette) -> str:
    return (
        palette_css(p)
        + marks_css(p)
        + """
.habit-name { font-weight: 600; }
.habit-note {
  font-size: 0.82rem;
  color: @moarchy_dim;
}
.streak-figure { font-size: 2.2rem; font-weight: 700; }
.stat-label {
  font-size: 0.78rem;
  color: @moarchy_dim;
  letter-spacing: 0.06em;
}
.daylabel {
  font-size: 0.72rem;
  color: @moarchy_dim;
}
.calendar-grid { padding: 2px; }
.section-heading {
  font-size: 0.78rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  color: @moarchy_dim;
}

/* --- the scoreboard ------------------------------------------------------ */

/* The ring reads its own `color` in its draw function, so setting it here is
   what makes a theme change repaint it along with everything else. */
.ring { color: @accent_color; }
.ring-figure {
  font-size: 1.05rem;
  font-weight: 700;
  font-feature-settings: "tnum";
}
.scoreboard {
  padding: 14px 16px;
  border-radius: 14px;
  background: @moarchy_surface;
}
.level-name {
  font-size: 1.05rem;
  font-weight: 700;
}
.level-note {
  font-size: 0.8rem;
  color: @moarchy_dim;
  font-feature-settings: "tnum";
}
.levelbar { min-height: 6px; }
.levelbar > trough,
.levelbar > trough > progress { min-height: 6px; border-radius: 3px; }

/* --- badges -------------------------------------------------------------- */

.badge {
  padding: 12px 6px;
  border-radius: 12px;
  background: @moarchy_surface;
  opacity: 0.45;
}
.badge.earned { opacity: 1; }
.badge-glyph {
  font-size: 1.7rem;
  color: @moarchy_dim;
}
.badge.earned .badge-glyph { color: @accent_color; }
.badge-name {
  font-size: 0.82rem;
  font-weight: 600;
}
.badge-note {
  font-size: 0.7rem;
  color: @moarchy_dim;
}
"""
    )
