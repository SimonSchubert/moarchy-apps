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

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
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
  readonly property color onAccent: Theme.onColor(accent)
  readonly property color border: theme.border
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
  readonly property int radius: theme.cornerRadius
  // A finger, or a cursor.
  readonly property int target: compact ? 44 : 38
  readonly property int chip: compact ? 34 : 32
  readonly property int gutter: compact ? 12 : 20
  readonly property var fs: ({
    xs: 11,
    sm: 13,
    md: 14,
    lg: 17,
    xl: compact ? 26 : 30,
    xxl: compact ? 34 : 40
  })
}
