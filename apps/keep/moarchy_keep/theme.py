"""The colours of a wall of notes.

The half that reads the phone's theme lives in `moarchy_ui.theme` and is the
same in every app here. This is the half that is Keep's own: the nine note
colours, and how far each hue is carried into the background to make a card.

Keep's identity is coloured notes, so it needs a palette of nine. The colours
are *derived* rather than chosen: each one is a hue from the active theme -- its
red, its orange, its green -- mixed a little way into the theme's own
background. On tokyo-night that gives the deep, desaturated cards a dark theme
wants; on rose-pine the same code gives pastels. The palette is Keep's shape and
the phone's colours.
"""

from __future__ import annotations

from moarchy_ui.theme import (  # noqa: F401  -- re-exported for the app
    COLORS,
    CURRENT_THEME,
    GNOME,
    Palette,
    fallback,
    load,
    mix,
    palette_css,
)

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
# How far a hue is carried into the background. Dark themes need less: their
# hues are bright against a near-black, and a third of the way over is a card
# that shouts. Light themes need more, or every note is the same white.
MIX_DARK = 0.24
MIX_LIGHT = 0.30


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
  border-color: @moarchy_line;
}

.note-card:hover {
  border-color: @moarchy_dim;
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
  color: @moarchy_dim;
  font-size: 0.9em;
}

.note-done {
  color: @moarchy_dim;
}

/* The checkbox a card draws. Not a widget -- see widgets.checkbox_glyph. */
.card-check {
  min-width: 12px;
  min-height: 12px;
  border: 1.5px solid @moarchy_dim;
  border-radius: 3px;
}

.card-check.checked {
  border-color: transparent;
  background-color: alpha(currentColor, 0.16);
  color: @moarchy_dim;
}

/* Section headings: PINNED / OTHERS. Small, wide-tracked, dim -- they label
 * without competing with the note titles under them. */
.section-heading {
  color: @moarchy_dim;
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
  color: @moarchy_dim;
}

/* Deliberately not ".bottom-bar": libadwaita puts that exact class on the box
 * Adw.ToolbarView wraps every bottom bar in, so a rule named for it also
 * painted the editor's "Edited ..." strip -- a white band across the foot of a
 * coral note. Our own name touches only our own bar. */
.keep-bottom-bar {
  background-color: @moarchy_surface;
  border-top: 1px solid @moarchy_line;
}

/* Colour picker. Circles, 48px, because a 24px swatch is a desktop control. */
.swatch {
  border-radius: 999px;
  min-width: 44px;
  min-height: 44px;
  padding: 0;
  border: 1px solid @moarchy_line;
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
  color: @moarchy_dim;
}

.editor-meta {
  color: @moarchy_dim;
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
  color: @moarchy_dim;
  padding-left: 4px;
  padding-right: 4px;
}

.dim-label-strong {
  color: @moarchy_dim;
}
"""


def stylesheet(dark_hint: bool = True) -> tuple[str, Palette]:
    """The whole stylesheet, and the palette it was built from."""
    palette = load() or fallback(dark_hint)
    return palette_css(palette) + note_css(palette) + WIDGETS, palette
