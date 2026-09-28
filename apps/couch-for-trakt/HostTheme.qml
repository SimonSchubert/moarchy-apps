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
//     shell.toml beside it. Read the way the shell's Commons/Color.qml reads
//     them, so the app and the shell agree on every colour.
//  3. Otherwise a plain palette, light or dark with the desktop.
//
// `qs.Commons` is a module the Omarchy shell puts on the import path. On a
// plain Quickshell it does not exist, and an import that cannot resolve fails
// the whole file at load time -- there is no catching it from the caller. So
// the import is compiled as a string, once, and the object it makes is kept:
// its properties are bindings, so a theme switch still reaches the app.
QtObject {
  id: root

  // The probe's object, whose properties are known only at run time.
  property var shell: null
  readonly property bool inShell: shell !== null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string themeDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/current/theme"

  property var file: ({})       // colors.toml
  property var menu: ({})       // shell.toml's [menu]
  readonly property bool hasFile: file.background !== undefined && file.foreground !== undefined
  readonly property bool useFile: hasFile && !inShell

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

  // Anywhere else: follow the desktop's light or dark preference, in the
  // palettes Panel.qml gives.
  // qmllint disable missing-property
  readonly property bool systemDark: Qt.styleHints.colorScheme !== Qt.ColorScheme.Light
  // qmllint enable missing-property
  property var plainDark: ({})
  property var plainLight: ({})
  readonly property var plain: systemDark ? plainDark : plainLight

  readonly property color background: inShell ? shell.background
    : useFile ? (hex(menu.background) || file.background) : plain.background
  readonly property color text: inShell ? shell.text
    : useFile ? (hex(menu.text) || file.foreground) : plain.text
  readonly property color muted: inShell ? shell.muted
    : useFile ? file.muted : plain.muted
  readonly property color accent: inShell ? shell.accent
    : useFile ? (file.accent || file.foreground) : plain.accent
  readonly property color border: inShell ? shell.border
    : useFile ? Qt.rgba(text.r, text.g, text.b, 0.25) : plain.border
  // Omarchy's own family is the fontconfig alias `monospace`, which is what
  // the shell resolves too: with a theme to follow, the app looks as it
  // does inside the shell.
  // qmllint disable missing-property
  readonly property string fontFamily: inShell ? shell.fontFamily : useFile ? "monospace" : Qt.application.font.family
  // qmllint enable missing-property
  readonly property int cornerRadius: inShell ? shell.cornerRadius : useFile ? 0 : 10

  function hex(v) { return typeof v === "string" && /^#[0-9A-Fa-f]{6}$/.test(v) ? v : "" }

  // colors.toml, key -> "#rrggbb", with the shell's fallbacks for a theme
  // that names only color0..color15.
  function parseColors(raw) {
    var out = ({})
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) out[m[1]] = m[2].toLowerCase()
    }
    if (!out.background && out.color0) out.background = out.color0
    if (!out.foreground && out.color7) out.foreground = out.color7
    if (!out.accent && out.color4) out.accent = out.color4
    if (!out.muted) out.muted = out.color8 || out.foreground
    return out
  }

  // The [menu] table of shell.toml: the colours the shell draws its own
  // windows in, which win over colors.toml's where a theme sets them.
  function parseMenu(raw) {
    var out = ({})
    var section = ""
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/^\s+|\s+$/g, "")
      var s = line.match(/^\[([A-Za-z0-9_.-]+)\]/)
      if (s) { section = s[1]; continue }
      if (section !== "menu") continue
      var kv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s#]+))/)
      if (kv) out[kv[1]] = kv[2] !== undefined ? kv[2] : kv[3] !== undefined ? kv[3] : kv[4]
    }
    return out
  }

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
      // Not in the shell: the theme files, or the palette above.
      shell = null
    }
  }
}
