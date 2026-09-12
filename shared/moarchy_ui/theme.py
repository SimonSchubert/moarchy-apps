"""Reading the phone's palette.

mobileomarchy's identity is that one `omarchy-theme-set` recolours the bar, the
drawer, the shade and the keyboard at once. An app that shipped its own colours
would be the one surface on the phone ignoring the theme, so every app here
reads the active theme and derives its own palette from it.

This module is the half that is the same in every app: find the theme, parse it,
fall back when it is not there, and mix one colour into another. What each app
does with the result -- Keep's nine note colours, Habits' four-step ramp -- is
the app's own business and lives in the app.

`~/.local/state/omarchy/current/theme` is a staged copy of the theme rather than
a symlink, which is what omarchy-theme-set maintains and omarchy-theme-current
reads. Following the copy means a theme switch is picked up without knowing
where themes are installed.

Everything degrades. With no Omarchy, no colors.toml, or a malformed one, the
GNOME palette below stands in and an app is themed, never broken, by the absence
of a file.
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

# The eight hue roles a theme is expected to name. Stand-ins are GNOME's own
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

HUES = tuple(GNOME)


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
    for role, default in GNOME.items():
        hues[role] = _colour(data, role, f"bright_{role}") or default

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

    Done here rather than with CSS's own mix() or alpha(): these need to be
    solid colours. A translucent shape over the window background is the same
    thing only until something is drawn behind it, and blending a layer per
    shape per frame is not free on a Mali-400 with no GL.
    """
    src, dst = _rgb(colour), _rgb(into)
    r, g, b = (round(s * amount + d * (1 - amount)) for s, d in zip(src, dst))
    return f"#{r:02x}{g:02x}{b:02x}"


def hue_of(palette: Palette, key: str) -> str:
    """A named hue, with the theme's green as the answer to a bad name."""
    return palette.hues.get(key) or palette.hues.get("green") or palette.accent


def palette_css(p: Palette) -> str:
    """Point libadwaita's named colours at the theme.

    Overriding the names rather than restyling widgets is what makes every stock
    widget -- rows, headers, entries, popovers, dialogs -- follow the theme
    without any app having to know they exist.

    The three `moarchy_*` names are ours, and are the ones an app's own
    stylesheet should build on, so that "the dim colour" means the same thing in
    every app on the phone.
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
@define-color success_color {p.hues["green"]};
@define-color moarchy_dim {p.dim};
@define-color moarchy_line {mix(p.foreground, p.background, 0.16)};
@define-color moarchy_surface {p.surface};
"""
