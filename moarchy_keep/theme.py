"""Colours: the app's own, and the phone's.

Two jobs, and they are the same job. Keep's identity is coloured notes, so this
app needs a palette of nine note colours. mobileomarchy's identity is that one
`omarchy-theme-set` recolours the bar, the drawer, the shade and the keyboard at
once, so a notes app that shipped Google's yellow and green would be the one
surface on the phone that ignored the theme.

So the note colours are *derived* rather than chosen: each one is a hue from the
active theme -- its red, its orange, its green -- mixed a little way into the
theme's own background. On tokyo-night that gives the deep, desaturated cards a
dark theme wants; on rose-pine the same code gives pastels. The palette is Keep's
shape and the phone's colours.

`~/.local/state/omarchy/current/theme` is a staged copy of the theme rather than
a symlink to it, which is what omarchy-theme-set maintains and what
omarchy-theme-current reads. Following the copy means a theme switch is picked up
without knowing where themes are installed.

Everything degrades. With no Omarchy, no colors.toml, or a malformed one, the
GNOME palette below stands in and the app is themed, never broken, by the
absence of a file.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

import tomllib

CURRENT_THEME = Path.home() / ".local" / "state" / "omarchy" / "current" / "theme"
COLORS = CURRENT_THEME / "colors.toml"

# Hex only. These values are interpolated into a stylesheet, so anything that is
# not plainly a colour is not going into it -- a theme is data, not code.
HEX = re.compile(r"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")

# The nine, in the order they appear in the picker: a 3x3 grid of 48px targets,
# which is what fits across 360px with room to be tapped. Each is (key, label,
# theme colour to derive it from). "default" is the note that has not been
# given a colour, and is the surface itself.
NOTE_COLOURS: tuple[tuple[str, str, str], ...] = (
    ("default", "Default", ""),
    ("coral", "Coral", "red"),
    ("peach", "Peach", "orange"),
    ("sand", "Sand", "yellow"),
    ("mint", "Mint", "green"),
    ("sage", "Sage", "cyan"),
    ("fog", "Fog", "blue"),
    ("dusk", "Dusk", "magenta"),
    ("clay", "Clay", "brown"),
)

COLOUR_KEYS = tuple(key for key, _, _ in NOTE_COLOURS)

# Stand-in hues, used when there is no Omarchy theme to read. GNOME's own
# palette, so an unthemed desktop looks deliberate rather than like a fallback.
GNOME = {
    "red": "#e01b24",
    "orange": "#ff7800",
    "yellow": "#f5c211",
    "green": "#33d17a",
    "cyan": "#00b8c4",
    "blue": "#3584e4",
    "magenta": "#c061cb",
    "brown": "#986a44",
}
GNOME_DARK = {"background": "#1d1d20", "surface": "#28282c", "foreground": "#ffffff"}
GNOME_LIGHT = {"background": "#fafafa", "surface": "#ffffff", "foreground": "#2e3436"}

# How far a hue is carried into the background. Dark themes need less: their
# hues are bright against a near-black, and a third of the way over is a card
# that shouts. Light themes need more, or every note is the same white.
MIX_DARK = 0.24
MIX_LIGHT = 0.30


@dataclass(frozen=True)
class Palette:
    accent: str
    background: str
    surface: str
    raised: str
    foreground: str
    dim: str
    hues: dict[str, str]
    dark: bool


def _colour(data: dict, *names: str) -> str:
    """First key that is present and is actually a colour."""
    for name in names:
        value = data.get(name)
        if isinstance(value, str) and HEX.match(value.strip()):
            return value.strip()
    return ""


def load(path: Path = COLORS) -> Palette | None:
    try:
        with path.open("rb") as fh:
            data = tomllib.load(fh)
    except (OSError, ValueError, tomllib.TOMLDecodeError):
        return None
    if not isinstance(data, dict):
        return None

    accent = _colour(data, "accent", "blue")
    background = _colour(data, "background")
    foreground = _colour(data, "bright_foreground", "foreground")
    if not (accent and background and foreground):
        # Missing any of these leaves half the app themed and half not, which
        # looks worse than not theming it at all.
        return None

    dark = str(data.get("mode", "dark")).lower() != "light"
    hues = {}
    for role, fallback in GNOME.items():
        hues[role] = _colour(data, role, f"bright_{role}") or fallback

    return Palette(
        accent=accent,
        background=background,
        surface=_colour(data, "lighter_background", "selection") or background,
        raised=_colour(data, "selection", "lighter_background") or background,
        foreground=foreground,
        dim=_colour(data, "dark_foreground", "muted") or foreground,
        hues=hues,
        dark=dark,
    )


def fallback(dark: bool) -> Palette:
    base = GNOME_DARK if dark else GNOME_LIGHT
    return Palette(
        accent="#3584e4",
        background=base["background"],
        surface=base["surface"],
        raised=base["surface"],
        foreground=base["foreground"],
        dim="#9a9996",
        hues=dict(GNOME),
        dark=dark,
    )


def _rgb(value: str) -> tuple[int, int, int]:
    text = value.lstrip("#")
    if len(text) == 3:
        text = "".join(c * 2 for c in text)
    return int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16)


def mix(colour: str, into: str, amount: float) -> str:
    """`amount` of `colour` over `into`, as a hex string.

    Done here rather than with CSS's own mix() or alpha(): the card needs a
    solid colour. A translucent card over the window background is the same
    thing only until something is drawn behind it -- the section heading
    scrolling under a card is exactly that -- and blending a layer per card per
    frame is not free on a Mali-400 with no GL.
    """
    src, dst = _rgb(colour), _rgb(into)
    r, g, b = (round(s * amount + d * (1 - amount)) for s, d in zip(src, dst))
    return f"#{r:02x}{g:02x}{b:02x}"


def note_colour(palette: Palette, key: str) -> str:
    """The actual fill of a note card, for a colour key."""
    if key == "default":
        return palette.surface
    role = next((r for k, _, r in NOTE_COLOURS if k == key), "")
    hue = palette.hues.get(role)
    if not hue:
        return palette.surface
    amount = MIX_DARK if palette.dark else MIX_LIGHT
    return mix(hue, palette.background, amount)


def palette_css(p: Palette) -> str:
    """Point libadwaita's named colours at the theme.

    Overriding the names rather than restyling widgets is what makes every stock
    widget -- rows, headers, entries, popovers -- follow the theme without this
    file having to know they exist.
    """
    return f"""
@define-color window_bg_color {p.background};
@define-color window_fg_color {p.foreground};
@define-color view_bg_color {p.background};
@define-color view_fg_color {p.foreground};
@define-color headerbar_bg_color {p.background};
@define-color headerbar_fg_color {p.foreground};
@define-color card_bg_color {p.surface};
@define-color card_fg_color {p.foreground};
@define-color dialog_bg_color {p.surface};
@define-color dialog_fg_color {p.foreground};
@define-color popover_bg_color {p.surface};
@define-color popover_fg_color {p.foreground};
@define-color accent_bg_color {p.accent};
@define-color accent_fg_color {p.background};
@define-color accent_color {p.accent};
@define-color keep_dim {p.dim};
@define-color keep_line {mix(p.foreground, p.background, 0.16)};
@define-color keep_bar {p.surface};
"""


def note_css(p: Palette) -> str:
    """One rule per note colour, for the card and for its swatch.

    Class names rather than inline styles so that a theme change is a single
    reload of this provider: every card already on screen repaints, without the
    grid knowing a theme exists.
    """
    rules = []
    for key, _, _ in NOTE_COLOURS:
        fill = note_colour(p, key)
        # Three selectors, and the two-class ones are not redundant. A card is
        # a GtkButton, so libadwaita's own `button:hover` -- one class and one
        # pseudo-class -- outranks a bare `.note-sand`, and the card would
        # revert to grey under the finger. `.note-card.note-sand` outranks it.
        rules.append(f".note-{key} {{ background-color: {fill}; }}")
        rules.append(f".note-card.note-{key} {{ background-color: {fill}; }}")
        rules.append(f".swatch.swatch-{key} {{ background-color: {fill}; }}")
    return "\n".join(rules)


# Named colours only below this line, so it is correct with or without a
# palette above it.
#
# No shadows and no gradients: this device has no usable GL context (Mali-400
# tops out at GLES 2.0, so GTK renders in software), and every blurred edge is
# then CPU-blended on a 1.15GHz A53 while the grid scrolls. Flat fills with
# radii cost nothing and read as more deliberate at this size anyway.
WIDGETS = """
/* The card. Keep's whole look is this shape repeated: a rounded rectangle,
 * flat fill, hairline outline, no shadow. */
.note-card,
.note-card:hover,
.note-card:active,
.note-card:focus {
  border-radius: 12px;
  border: 1px solid transparent;
  padding: 0;
  min-height: 0;
  /* libadwaita draws buttons with a background *image* and a shadow. Setting
   * only background-color leaves both on top of it, which is why an unstyled
   * attempt at this looked like a grey button with a coloured edge. */
  background-image: none;
  box-shadow: none;
  /* A card is a GtkButton, and libadwaita sets every button's text bold. On a
   * button with a one-word label that is right; on one holding a paragraph of
   * someone's note it is a wall of bold. Only the title is bold here, and it
   * says so itself. */
  font-weight: normal;
  transition: none;
}

/* Only the uncoloured card is outlined. A coloured one already separates
 * itself from the background, and an outline on top of that reads as a box
 * drawn around a colour rather than as one object. */
.note-card.note-default {
  border-color: @keep_line;
}

.note-card:hover {
  border-color: @keep_dim;
}

.note-title {
  font-weight: bold;
  font-size: 1.05em;
}

.note-body,
.note-item {
  font-size: 0.95em;
}

.note-more,
.note-empty-line {
  color: @keep_dim;
  font-size: 0.9em;
}

.note-done {
  color: @keep_dim;
}

/* The checkbox a card draws. Not a widget -- see widgets.checkbox_glyph. */
.card-check {
  min-width: 12px;
  min-height: 12px;
  border: 1.5px solid @keep_dim;
  border-radius: 3px;
}

.card-check.checked {
  border-color: transparent;
  background-color: alpha(currentColor, 0.16);
  color: @keep_dim;
}

/* Section headings: PINNED / OTHERS. Small, wide-tracked, dim -- they label
 * without competing with the note titles under them. */
.section-heading {
  color: @keep_dim;
  font-size: 0.75em;
  font-weight: bold;
  letter-spacing: 0.12em;
  padding-left: 6px;
}

/* The search field in the header bar. Keep's is a pill that fills the width,
 * which on this screen is also the largest tap target that fits there. */
.search-pill {
  border-radius: 999px;
  background-color: @card_bg_color;
  min-height: 40px;
}

/* The bottom bar: "Take a note..." and the two ways to start one. It is the
 * app's only permanent control, so it is thumb-height and full-width rather
 * than a floating button in a corner. */
.take-note {
  min-height: 52px;
  padding-left: 18px;
  padding-right: 18px;
  border-radius: 0;
  font-size: 1.0em;
  color: @keep_dim;
}

/* Deliberately not ".bottom-bar": libadwaita puts that exact class on the box
 * Adw.ToolbarView wraps every bottom bar in, so a rule named for it also
 * painted the editor's "Edited ..." strip -- a white band across the foot of a
 * coral note. Our own name touches only our own bar. */
.keep-bottom-bar {
  background-color: @keep_bar;
  border-top: 1px solid @keep_line;
}

/* Colour picker. Circles, 48px, because a 24px swatch is a desktop control. */
.swatch {
  border-radius: 999px;
  min-width: 44px;
  min-height: 44px;
  padding: 0;
  border: 1px solid @keep_line;
}

.swatch:checked,
.swatch.selected {
  border: 2px solid @accent_color;
}

/* The editor. A note being edited should look like the card it came from, not
 * like a form: no entry frames, no separators, just text on the note's colour.
 *
 * The colour is on the page rather than on a card inside it, so the header bar
 * has to stop painting its own -- otherwise the top 48px of a coral note is
 * grey and the join reads as a rendering bug. */
.note-page > headerbar,
.note-page headerbar,
.note-page scrolledwindow,
.note-page textview,
.note-page textview text {
  background-color: transparent;
  background-image: none;
  box-shadow: none;
}

.note-page headerbar {
  border-bottom: none;
}

.editor-title,
.editor-item {
  background: none;
  background-image: none;
  border: none;
  box-shadow: none;
  outline: none;
  padding: 0;
  min-height: 0;
}

.editor-title {
  font-size: 1.4em;
  font-weight: bold;
}

.editor-body {
  background: none;
  font-size: 1.05em;
}

.editor-body text {
  background: none;
}

.editor-placeholder {
  color: @keep_dim;
}

.editor-meta {
  color: @keep_dim;
  font-size: 0.85em;
}

.note-page .meta-bar {
  background-color: transparent;
}

/* Checklist rows are 44px so a checkbox is a thumb target, and the delete
 * button is always visible -- there is no hover on a touchscreen to reveal it. */
.editor-item-row {
  min-height: 44px;
}

.checked-heading,
.add-item {
  color: @keep_dim;
  padding-left: 4px;
  padding-right: 4px;
}

.dim-label-strong {
  color: @keep_dim;
}
"""


def stylesheet(dark_hint: bool = True) -> tuple[str, Palette]:
    """The whole stylesheet, and the palette it was built from."""
    palette = load() or fallback(dark_hint)
    return palette_css(palette) + note_css(palette) + WIDGETS, palette
