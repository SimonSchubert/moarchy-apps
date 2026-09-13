"""The colours of a meter.

The half that reads the phone's theme lives in `moarchy_ui.theme` and is the
same in every app here. This is the half that is Vitals' own: which hue a
measurement is drawn in, and the ramp that turns "how hard is this core
working" into a colour.

Two rules, and they are the whole file.

**One measurement, one hue, everywhere it appears.** The processor is the
theme's blue in the overview figure, in the graph behind it, in the per-core
bars, and in the processor column of the task list. Memory is the green in all
four. A phone screen is too small to carry a legend, so the colour *is* the
legend -- and it only works if nothing else on the screen is also blue.

**Heat is a ramp, not a hue.** "This core is at 97%" and "this one is at 12%"
have to be tellable apart at arm's length in daylight, which a single colour at
two lengths does not manage. So load runs the theme's own green, yellow and red,
in that order, and the reading is the colour before it is the number.

Everything drawn with cairo is handed the palette rather than reading CSS: a
draw function cannot resolve a stylesheet colour, and the alternative -- one CSS
class per widget whose `color` the draw function reads -- buys a single colour
per widget, which is not enough for a graph with a fill, a line and a track.
Reversi and Solitaire hand the board its palette for the same reason.
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

# Which hue role each measurement is drawn in. Named roles rather than colours,
# so a theme with an unusual green gets an unusual green here too.
#
# The pairs are chosen to be told apart rather than to be pretty: download and
# upload sit next to each other on one graph, and cyan against magenta survives
# both a light theme and a phone screen at half brightness. Read and write are
# the same argument one row down.
SERIES = {
    "cpu": "blue",
    "memory": "green",
    "swap": "yellow",
    "cache": "cyan",
    "rx": "cyan",
    "tx": "magenta",
    "read": "blue",
    "write": "orange",
    "load": "orange",
    "battery": "green",
    # Violet rather than the obvious brown: a storage bar sits under a green
    # memory bar and a blue processor graph, and the theme's brown is the one
    # hue that reads as "a colour that went wrong" on half the palettes.
    "disk": "magenta",
}

# The three rungs of the heat ramp, and where they start. A core at two thirds
# is working; at nine tenths it is the reason the phone is warm. Thresholds
# rather than a continuous blend because a continuous one is a single colour
# that changes too slowly to notice.
HEAT = ((0.0, "green"), (0.65, "yellow"), (0.88, "red"))

# Degrees celsius at which an SoC reading stops being unremarkable. A phone
# under load sits in the sixties; a phone in the eighties is throttling.
WARM_C = 62.0
HOT_C = 78.0

# How much of the hue is carried over the background for a graph's fill and for
# the track a meter is drawn in. Solid colours, mixed here: a translucent fill
# would be blended per shape per frame, and there is no GL on this hardware.
FILL = 0.30
TRACK = 0.16

# A fill for a series drawn as a shape rather than as a quantity -- the memory
# graph, which sits in the middle of its scale and is a solid block at FILL.
# Enough to read as a body under the line, not enough to be a wall.
GHOST = 0.10


def series(palette: Palette, key: str) -> str:
    """The colour one measurement is always drawn in."""
    if key == "cpu":
        # The processor is the app's headline number, so it gets the theme's
        # accent rather than its blue -- which on most themes is the same
        # colour, and on a theme that sets an accent is the one the rest of the
        # phone is already using.
        return palette.accent
    return hue_of(palette, SERIES.get(key, "green"))


def heat(palette: Palette, fraction: float) -> str:
    """Green, yellow or red, by how hard something is working."""
    role = HEAT[0][1]
    for threshold, name in HEAT:
        if fraction >= threshold:
            role = name
    return hue_of(palette, role)


def temperature_class(celsius: float | None) -> str:
    """The CSS class a temperature reading wears."""
    if celsius is None:
        return ""
    if celsius >= HOT_C:
        return "hot"
    if celsius >= WARM_C:
        return "warm"
    return ""


def meters_css(p: Palette) -> str:
    """One rule per measurement, for the things that are widgets.

    Progress bars are libadwaita's own, so they are recoloured through their
    trough and progress nodes rather than replaced -- which keeps their height,
    their radius and their animation, and means a theme change is one reload.
    """
    rules = [
        f"""
.meter > trough,
.meter > trough > progress {{
  min-height: 10px;
  border-radius: 5px;
}}
.meter > trough {{ background-color: {mix(p.foreground, p.background, TRACK)}; }}
.meter.thin > trough,
.meter.thin > trough > progress {{ min-height: 6px; border-radius: 3px; }}
"""
    ]
    for key in SERIES:
        colour = series(p, key)
        rules.append(
            f".meter.{key} > trough > progress {{ background-color: {colour}; }}"
        )
        rules.append(f".ink-{key} {{ color: {colour}; }}")
    for role in ("green", "yellow", "red"):
        rules.append(f".heat-{role} {{ color: {hue_of(p, role)}; }}")
    return "\n".join(rules)


def stylesheet(p: Palette) -> str:
    return (
        palette_css(p)
        + meters_css(p)
        + f"""
/* --- panels --------------------------------------------------------------- */

/* Not libadwaita's `.card`: these carry their own padding and their own radius,
   and a rule that redefined `.card` would reach every boxed list in the app. */
.panel {{
  background: @moarchy_surface;
  border-radius: 14px;
  padding: 12px 14px;
}}
.panel-flat {{
  background: transparent;
  padding: 0;
}}

/* --- figures -------------------------------------------------------------- */

/* tnum on everything that counts. Without it a figure ticking from 19% to 20%
   moves every glyph left of it, and four of these on one screen makes the whole
   panel twitch twice a second. */
.figure {{
  font-size: 1.9rem;
  font-weight: 700;
  font-feature-settings: "tnum";
}}
.figure-small {{
  font-size: 1.15rem;
  font-weight: 700;
  font-feature-settings: "tnum";
}}
.figure-unit {{
  font-size: 0.8rem;
  color: @moarchy_dim;
  font-feature-settings: "tnum";
}}
.value {{
  font-feature-settings: "tnum";
}}
.label {{
  font-size: 0.78rem;
  color: @moarchy_dim;
  letter-spacing: 0.06em;
  text-transform: uppercase;
}}
.label.literal {{
  text-transform: none;
  letter-spacing: 0;
}}
.note {{
  font-size: 0.82rem;
  color: @moarchy_dim;
  font-feature-settings: "tnum";
}}
.section-heading {{
  font-size: 0.78rem;
  font-weight: 700;
  letter-spacing: 0.08em;
  color: @moarchy_dim;
}}
.warm {{ color: {hue_of(p, "yellow")}; }}
.hot {{ color: {hue_of(p, "red")}; }}

/* --- cores ---------------------------------------------------------------- */

.corelabel {{
  font-size: 0.68rem;
  color: @moarchy_dim;
  font-feature-settings: "tnum";
}}

/* --- the task list -------------------------------------------------------- */

/* Rows are built by hand rather than from Adw.ActionRow, because the figures on
   the right have to line up in a column of their own and a suffix widget lines
   up with whatever is above it. */
.task-row {{ padding: 8px 12px; }}
.task-name {{ font-weight: 600; }}
.task-note {{
  font-size: 0.78rem;
  color: @moarchy_dim;
  font-feature-settings: "tnum";
}}
.task-figure {{
  font-weight: 600;
  font-feature-settings: "tnum";
}}
.task-sub {{
  font-size: 0.78rem;
  color: @moarchy_dim;
  font-feature-settings: "tnum";
}}
.command {{
  font-family: monospace;
  font-size: 0.78rem;
  color: @moarchy_dim;
}}

/* --- the tab bar ---------------------------------------------------------- */

/* The switcher is at the bottom, where a thumb is. That is the one structural
   difference from every desktop system monitor, and it is why the bar needs a
   line above it: without one the tabs float over whatever the page scrolled
   under them. */
.tabbar {{ border-top: 1px solid @moarchy_line; }}
"""
    )
