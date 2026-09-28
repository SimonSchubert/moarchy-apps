import QtQuick
import Quickshell
import Quickshell.Io
import "Theme.js" as Theme

// The colours, font and corner radius the app is drawn with.
//
// Three sources, best first:
//
//  1. Inside the Omarchy shell, the shell's own `qs.Commons`, so the app
//     changes with the shell's theme in the same frame.
//  2. Anywhere Omarchy has set a theme -- a desktop, or Omarchy Mobile, where
//     the app runs as its own process -- the files the shell reads that from:
//     ~/.local/state/omarchy/current/theme/colors.toml, and the [menu] of
//     shell.toml beside it. Read the way Commons/Color.qml reads them.
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
  // Whether the colours are a theme's rather than the plain palette's.
  readonly property bool themed: inShell || useFile

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
    onLoaded: root.file = Theme.parseColors(text())
    onLoadFailed: root.file = ({})
    onFileChanged: reload()
  }
  property FileView menuView: FileView {
    path: root.home ? root.themeDir + "/shell.toml" : ""
    watchChanges: true
    printErrors: false
    onLoaded: root.menu = Theme.parseMenu(text())
    onLoadFailed: root.menu = ({})
    onFileChanged: reload()
  }

  // Anywhere else: follow the desktop's light or dark preference.
  // qmllint disable missing-property
  readonly property bool systemDark: Qt.styleHints.colorScheme !== Qt.ColorScheme.Light
  // qmllint enable missing-property
  readonly property var plain: Theme.fallback(systemDark)

  readonly property color background: inShell ? shell.background
    : useFile ? (Theme.hex(menu.background) || file.background) : plain.background
  readonly property color text: inShell ? shell.text
    : useFile ? (Theme.hex(menu.text) || file.foreground) : plain.text
  readonly property color muted: inShell ? shell.muted
    : useFile ? file.muted : plain.muted
  readonly property color accent: inShell ? shell.accent
    : useFile ? (file.accent || file.foreground) : plain.accent
  readonly property color border: inShell ? shell.border
    : useFile ? Qt.rgba(text.r, text.g, text.b, 0.25) : plain.border
  // Omarchy's own family is the fontconfig alias `monospace`, which is what
  // the shell resolves too: with Omarchy's theme comes Omarchy's type.
  // qmllint disable missing-property
  readonly property string fontFamily: inShell ? shell.fontFamily
    : useFile ? "monospace" : Qt.application.font.family
  // qmllint enable missing-property
  readonly property int cornerRadius: inShell ? shell.cornerRadius : 10

  // The theme's hues by name -- red, green, yellow, blue, magenta, cyan,
  // orange -- or "" where it has none. Read from the file inside the shell as
  // well: the shell exposes only its urgent red.
  function hue(name) { return themed ? Theme.hex(file[name]) : "" }

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
      // Not in the shell: the theme files, or the plain palette above.
      shell = null
    }
  }
}
