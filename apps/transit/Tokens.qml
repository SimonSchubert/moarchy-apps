import QtQuick
import "Theme.mjs" as Theme

// Everything the views draw with, derived from the theme and from how wide
// the window is. Views read these as `app.ui.<name>`: a colour written into a
// view is a view that ignores the theme.
QtObject {
  id: t

  required property HostTheme theme
  property bool compact: false

  function alpha(c, a) { var x = Qt.color(c); return Qt.rgba(x.r, x.g, x.b, a) }
  // A theme's hue where it names one that looks like its name and reads on
  // its background -- small text is drawn in these -- and ours where not.
  function hue(name, fallback) {
    var h = theme.hue(name)
    return h && Theme.looksLike(h, name) && Theme.contrast(h, bg) >= 3 ? h : fallback
  }

  readonly property bool dark: Theme.luminance(theme.background) < 0.5
  readonly property color bg: theme.background
  readonly property color text: theme.text
  readonly property color muted: Theme.mutedReads(theme.muted, theme.background)
    ? theme.muted : Qt.tint(bg, alpha(text, 0.62))
  // An accent is text too (a countdown, a chosen chip): one that all but
  // vanishes into the page gives way to the text colour.
  readonly property color accent: Theme.contrast(theme.accent, theme.background) >= 1.8 ? theme.accent : text
  readonly property color border: theme.border
  readonly property color surface: Qt.tint(bg, alpha(text, dark ? 0.06 : 0.04))
  readonly property color surfaceHigh: Qt.tint(bg, alpha(text, dark ? 0.12 : 0.08))
  // No hover on a touch screen: a finger leaves the last row it lifted from
  // looking pointed at.
  readonly property color hover: compact ? "transparent" : alpha(text, 0.06)
  readonly property color pressed: alpha(text, 0.12)
  readonly property color accentSoft: alpha(accent, 0.16)
  readonly property color divider: alpha(text, 0.08)

  readonly property var fallback: Theme.state(dark)
  readonly property color ok: hue("green", fallback.ok)
  readonly property color late: hue("red", fallback.late)
  readonly property color warn: hue("yellow", fallback.warn)
  readonly property color lateSoft: alpha(late, 0.14)
  readonly property color warnSoft: alpha(warn, 0.16)
  readonly property color okSoft: alpha(ok, 0.14)
  readonly property color star: hue("yellow", fallback.star)

  readonly property string font: theme.fontFamily
  readonly property int radius: Math.max(6, Math.min(12, theme.cornerRadius))
  readonly property int target: compact ? 44 : 38
  readonly property int chip: compact ? 36 : 32
  readonly property var fs: ({
    xs: 11,
    sm: 13,
    md: 14,
    lg: 17,
    xl: 20,
    xxl: compact ? 26 : 30
  })
}
