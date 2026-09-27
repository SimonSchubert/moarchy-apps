import QtQuick
import Quickshell
import Quickshell.Io

// The colours, font and corner radius the app is drawn with.
//
// Three sources, best first:
//
//  1. Inside the Omarchy shell, the shell's own `qs.Commons`, so the app
//     changes with the shell's theme in the same frame.
//  2. Anywhere Omarchy has set a theme -- a desktop, or Omarchy Mobile, where
//     the app runs as its own process -- the files the shell reads that from:
//     ~/.local/state/omarchy/current/theme/colors.toml, and the [menu] of
//     shell.toml beside it. Read the way Commons/Color.qml reads them, so the
//     app and the shell agree on every colour.
//  3. Otherwise a plain palette, light or dark with the desktop.
//
// Settings can set the look to light or dark instead of the theme.
//
// `qs.Commons` is a module the Omarchy shell puts on the import path. On a
// plain Quickshell it does not exist, and an import that cannot resolve fails
// the whole file at load time -- there is no catching it from the caller. So
// the import is compiled as a string, once, and the object it makes is kept:
// its properties are bindings, so a theme switch still reaches the app.
QtObject {
  id: root

  property QtObject shell: null
  readonly property bool inShell: shell !== null

  // "theme" (the default: the shell's, or Omarchy's theme files), "system"
  // (the desktop's light or dark), "light" or "dark".
  property string appearance: "theme"
  readonly property bool forced: appearance === "light" || appearance === "dark"

  // ------------------------------------------------------------ the files

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string themeDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/current/theme"

  property var file: ({})       // colors.toml, key -> "#rrggbb"
  property var menu: ({})       // shell.toml's [menu], key -> value
  readonly property bool hasFile: file.background !== undefined && file.foreground !== undefined
  readonly property bool useFile: hasFile && !inShell && appearance === "theme"
  readonly property bool themed: (inShell || useFile) && !forced

  function parseColors(raw) {
    var out = ({})
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) out[m[1]] = m[2]
    }
    // The fallbacks Color.qml applies for a theme without the named keys.
    if (!out.background && out.color0) out.background = out.color0
    if (!out.foreground && out.color7) out.foreground = out.color7
    if (!out.accent && out.color4) out.accent = out.color4
    if (!out.muted) out.muted = out.color8 || out.foreground
    if (!out.red && out.color1) out.red = out.color1
    if (!out.green && out.color2) out.green = out.color2
    if (!out.yellow && out.color3) out.yellow = out.color3
    if (!out.blue && out.color4) out.blue = out.color4
    if (!out.magenta && out.color5) out.magenta = out.color5
    if (!out.cyan && out.color6) out.cyan = out.color6
    return out
  }

  function parseMenu(raw) {
    var out = ({})
    var section = ""
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/^\s+|\s+$/g, "")
      var s = line.match(/^\[([A-Za-z0-9_-]+)\]/)
      if (s) { section = s[1]; continue }
      if (section !== "menu") continue
      var kv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']?([^"'#\s]+)/)
      if (kv) out[kv[1]] = kv[2]
    }
    return out
  }

  function hex(v) { return typeof v === "string" && /^#[0-9A-Fa-f]{6}$/.test(v) ? v : "" }

  // A theme switch rewrites these files. They are watched, and read again
  // whenever the window opens, which covers a watch the rewrite broke.
  function reload() {
    colorsView.reload()
    menuView.reload()
  }

  property FileView colorsView: FileView {
    path: root.home ? root.themeDir + "/colors.toml" : ""
    watchChanges: true
    printErrors: false
    onLoaded: root.file = root.parseColors(text())
    onLoadFailed: root.file = ({})
    onFileChanged: reload()
  }
  property FileView menuView: FileView {
    path: root.home ? root.themeDir + "/shell.toml" : ""
    watchChanges: true
    printErrors: false
    onLoaded: root.menu = root.parseMenu(text())
    onLoadFailed: root.menu = ({})
    onFileChanged: reload()
  }

  // ------------------------------------------------------------ the palette

  readonly property bool systemDark: appearance === "dark" ? true : appearance === "light" ? false
    : Qt.styleHints.colorScheme !== Qt.ColorScheme.Light

  readonly property color background: !forced && inShell ? shell.background
    : useFile ? (hex(menu.background) || file.background)
    : (systemDark ? "#1e1e2e" : "#fafafa")
  readonly property color text: !forced && inShell ? shell.text
    : useFile ? (hex(menu.text) || file.foreground)
    : (systemDark ? "#e6e6ef" : "#1f1f28")
  readonly property color muted: !forced && inShell ? shell.muted
    : useFile ? file.muted
    : (systemDark ? "#9a9aae" : "#6b6b78")
  // Blue rather than a warm colour: the accent is the processor's colour
  // here, and a red or orange one would read as "under load" at a glance.
  readonly property color accent: !forced && inShell ? shell.accent
    : useFile ? (file.accent || file.foreground)
    : (systemDark ? "#60a5fa" : "#2563eb")
  readonly property color border: !forced && inShell ? shell.border
    : useFile ? Qt.rgba(text.r, text.g, text.b, 0.25)
    : (systemDark ? "#3a3a4e" : "#d8d8e0")
  // Omarchy's own family is the fontconfig alias `monospace`, which is what
  // the shell resolves too.
  readonly property string fontFamily: !forced && inShell ? shell.fontFamily
    : useFile ? "monospace" : Qt.application.font.family
  readonly property int cornerRadius: !forced && inShell ? shell.cornerRadius : 10

  // The theme's hues by name, for the load ramp and the series colours, or
  // "" where it has none. Read from the file inside the shell as well: the
  // shell exposes only its urgent red.
  function hue(name) { return themed ? hex(file[name]) : "" }

  function probe(parent) {
    try {
      shell = Qt.createQmlObject(
        "import QtQuick\nimport qs.Commons\n" +
        "QtObject {\n" +
        "  readonly property color background: Color.menu.background\n" +
        "  readonly property color text: Color.menu.text\n" +
        "  readonly property color muted: Color.muted\n" +
        "  readonly property color accent: Color.accent\n" +
        "  readonly property color border: Color.menu.border\n" +
        "  readonly property string fontFamily: Style.font.family\n" +
        "  readonly property int cornerRadius: Style.cornerRadius\n" +
        "}",
        parent, "OmarchyThemeProbe")
    } catch (e) {
      // Not in the shell: the theme files, or the fallback palette.
      shell = null
    }
  }
}
