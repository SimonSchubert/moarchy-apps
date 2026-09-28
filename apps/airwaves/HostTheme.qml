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
//     Airwaves runs as its own process -- the files the shell reads that
//     from: ~/.local/state/omarchy/current/theme/colors.toml, and the [menu]
//     of shell.toml beside it.
//  3. Otherwise Airwaves' own palette, light or dark with the desktop.
//
// Outside the shell `appearance` can pick light or dark, or the desktop's
// choice, instead of the theme. Inside it the shell's theme is the look.
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

  // "theme" (the shell's, or Omarchy's theme files), "system" (the desktop's
  // light or dark), "light" or "dark".
  property string appearance: "theme"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string themeDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/current/theme"

  property var file: ({})       // colors.toml
  property var menu: ({})       // shell.toml's [menu]
  readonly property bool hasFile: file.background !== undefined && file.foreground !== undefined
  // Whether there is a theme to follow at all; Settings offers it only then.
  readonly property bool hasTheme: inShell || hasFile
  readonly property bool useFile: hasFile && !inShell && appearance === "theme"

  // A theme switch rewrites these files, sometimes by replacing them, which
  // ends a watch. So they are also read again whenever the window opens.
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

  // qmllint disable missing-property
  readonly property bool systemDark: appearance === "dark" ? true : appearance === "light" ? false
    : Qt.styleHints.colorScheme !== Qt.ColorScheme.Light
  // qmllint enable missing-property
  readonly property var plain: Theme.fallback(systemDark)

  // From the files: what the shell's own windows use, where it says.
  readonly property string fileBackground: Theme.hex(menu.background) || file.background || ""
  readonly property string fileText: Theme.hex(menu.text) || file.foreground || ""

  // qmllint disable missing-property
  readonly property color background: inShell ? shell.background
    : useFile ? fileBackground : plain.background
  readonly property color text: inShell ? shell.text
    : useFile ? fileText : plain.text
  // A theme's muted that is really a border colour is the text, faded.
  readonly property color muted: inShell ? shell.muted
    : !useFile ? plain.muted
    : Theme.mutedReads(file.muted, fileBackground) ? file.muted : Qt.tint(background, Qt.rgba(text.r, text.g, text.b, 0.62))
  readonly property color accent: inShell ? shell.accent
    : !useFile ? plain.accent
    : file.accent && Theme.accentReads(file.accent, fileBackground) ? file.accent : fileText
  readonly property color border: inShell ? shell.border
    : useFile ? Qt.rgba(text.r, text.g, text.b, 0.25) : plain.border
  readonly property string fontFamily: inShell ? shell.fontFamily : Qt.application.font.family
  readonly property int cornerRadius: inShell ? shell.cornerRadius : 10
  // qmllint enable missing-property

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
