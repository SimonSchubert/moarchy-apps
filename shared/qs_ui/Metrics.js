// Numbers every plugin chrome should mean the same way.
//
// 44 is the shell's thumb floor. 40 is Keep's pill search: large enough to
// hit, short enough to sit in an AppBar. Type roles are multiples of a body
// size: the shell's own when we run inside it, BODY when we do not.
.pragma library

var TARGET = 44
// Material's 24dp icon is ~20dp of ink inside the asset. Adwaita symbolics
// are drawn to the edges of their 16px canvas, so the same pixel size reads
// ~1.2× larger. ICON is the Material-named size; ICON_INK is what we draw.
var ICON = 22
var ICON_INK = 18
var PILL = 40
var FAB = 56
var CARD_RADIUS = 12
var CHECK = 22
var MENU_WIDTH = 220
var MENU_ROW = 40
var BOTTOM_NAV = 56
var FONT = "Adwaita Sans"
// What Style.font.body is on a stock image, and what every type role
// multiplies when the shell is not there to say otherwise.
var BODY = 16

// Motion. One turn of a refresh icon while something is in flight, and the
// press feedback every control shares. Slow enough to read as "working"
// rather than "spinning", which also costs a Mali-400 less.
var SPIN_MS = 1000
var PRESS_MS = 120

// The shell's body size inside omarchy-shell, BODY anywhere else.
//
// `qs.Commons` is a module the plugin host puts on the import path. On a
// plain Quickshell it does not exist, and an import that cannot resolve
// fails the whole file at load time -- there is no catching it from the
// caller. Compiling that import as a string is what makes it optional.
// It runs once per app, at startup, and yields an int; nothing here is
// consulted again, let alone per frame.
function shellBody(parent) {
  try {
    var probe = Qt.createQmlObject(
      "import QtQuick\nimport qs.Commons\n" +
      "QtObject { readonly property int body: Style.font.body }",
      parent, "ShellStyleProbe")
    if (!probe) return BODY
    var body = probe.body
    probe.destroy()
    return body > 0 ? body : BODY
  } catch (e) {
    return BODY
  }
}

function typeSize(body, role) {
  var b = body || BODY
  if (role === "title") return Math.round(b * 1.4)
  if (role === "subtitle") return Math.round(b * 1.15)
  if (role === "body") return Math.round(b)
  if (role === "caption") return Math.round(b * 0.85)
  if (role === "overline") return Math.round(b * 0.75)
  return Math.round(b)
}
