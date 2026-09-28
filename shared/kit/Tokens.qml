import QtQuick
import "Theme.js" as Theme

// Everything an app draws with, derived from the theme and from how wide the
// window is. Widgets read these as `app.ui.<name>` and nothing else: a colour
// or a size written into a view is a view that ignores the theme.
//
// An app that needs more -- Vitals' series colours, a game's piece colours --
// declares its own Tokens with the extra properties added:
//
//   ui: Tokens {
//     theme: root.hostTheme; compact: root.compact
//     readonly property color cpu: accent
//   }
QtObject {
  id: t

  required property HostTheme theme
  property bool compact: false

  // A colour at an opacity. `c` may be a color or a "#rrggbb" string: a
  // string has no .r, and Qt.rgba(undefined, ...) is black.
  function alpha(c, a) { var x = Qt.color(c); return Qt.rgba(x.r, x.g, x.b, a) }
  // A theme's hue by name, or the fallback given for this palette.
  function hue(name, darkFallback, lightFallback) {
    return theme.hue(name) || (dark ? darkFallback : lightFallback)
  }

  readonly property bool dark: Theme.isDark(theme.background)
  readonly property color bg: theme.background
  readonly property color text: theme.text
  readonly property color muted: Theme.mutedReads(theme.muted, theme.background)
    ? theme.muted : Qt.tint(bg, alpha(text, 0.62))
  readonly property color accent: theme.accent
  // Text on a filled accent. Not `onAccent`: a name that is `on` and a
  // capital is read as a signal handler, and the property comes out black.
  readonly property color inkOnAccent: Theme.onColor(accent)
  readonly property color border: theme.border
  // The rule every box is drawn with: a solid line a step off the page, which
  // is what a square screen is made of. The theme's border when it reads,
  // otherwise the text mixed into the page.
  readonly property color line: Math.abs(Theme.luminance(theme.border) - Theme.luminance(theme.background)) >= 0.06
    ? theme.border : Qt.tint(bg, alpha(text, dark ? 0.16 : 0.2))
  readonly property color surface: Qt.tint(bg, alpha(text, dark ? 0.05 : 0.035))
  readonly property color surfaceHigh: Qt.tint(bg, alpha(text, dark ? 0.10 : 0.07))
  // The inside of a graph, a track or a board: a step down from the card.
  readonly property color well: Qt.tint(bg, alpha(text, dark ? 0.09 : 0.065))
  // No hover on a touch screen: a finger leaves the last row it lifted from
  // looking pointed at.
  readonly property color hover: compact ? "transparent" : alpha(text, 0.06)
  readonly property color pressed: alpha(text, 0.12)
  readonly property color selected: alpha(accent, 0.14)
  readonly property color accentSoft: alpha(accent, 0.16)
  readonly property color divider: alpha(text, 0.08)
  readonly property color scrim: alpha("#000000", 0.45)

  // States, from the theme's own hues where it names them.
  readonly property color good: hue("green", "#4ade80", "#16a34a")
  readonly property color warn: hue("yellow", "#facc15", "#ca8a04")
  readonly property color bad: hue("red", "#f87171", "#dc2626")

  readonly property string font: theme.fontFamily
  // Omarchy is square: 0 unless the theme rounds its windows.
  readonly property int radius: theme.cornerRadius
  // A shape that is a pill where corners are rounded and a box where they are
  // not: buttons, badges, the phone's tab marker. Never a disc or a ring --
  // a nought, a peg or an avatar is round because it is round.
  function round(h) { return radius > 0 ? h / 2 : 0 }
  // The small uppercase labels -- a section, a badge, a button -- are spaced
  // out by this many pixels a letter.
  readonly property real tracking: 1.2
  // A finger, or a cursor.
  readonly property int target: compact ? 44 : 38
  readonly property int chip: compact ? 34 : 32
  readonly property int gutter: compact ? 12 : 20
  // A monospace face is wider than a proportional one at the same size, so
  // the scale is a step smaller than it would be in Adwaita Sans.
  readonly property var fs: ({
    xs: 11,
    sm: 12,
    md: 13,
    lg: 15,
    xl: compact ? 22 : 26,
    xxl: compact ? 30 : 36
  })
}
