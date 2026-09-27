import QtQuick

// The colours, font and corner radius the app is drawn with: Omarchy's own
// inside its shell, a plain palette on any other Quickshell.
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

  // Anywhere else: follow the desktop's light or dark preference, unless
  // Settings picked one.
  property string appearance: "system"
  readonly property bool systemDark: appearance === "dark" ? true : appearance === "light" ? false
    : Qt.styleHints.colorScheme !== Qt.ColorScheme.Light

  readonly property color background: inShell ? shell.background : (systemDark ? "#1e1e2e" : "#fafafa")
  readonly property color text: inShell ? shell.text : (systemDark ? "#e6e6ef" : "#1f1f28")
  readonly property color muted: inShell ? shell.muted : (systemDark ? "#9a9aae" : "#6b6b78")
  readonly property color accent: inShell ? shell.accent : (systemDark ? "#fb7185" : "#e11d48")
  readonly property color border: inShell ? shell.border : (systemDark ? "#3a3a4e" : "#d8d8e0")
  readonly property string fontFamily: inShell ? shell.fontFamily : Qt.application.font.family
  readonly property int cornerRadius: inShell ? shell.cornerRadius : 10

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
      // Not in the shell: the fallback palette above.
      shell = null
    }
  }
}
