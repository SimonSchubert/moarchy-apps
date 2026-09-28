import QtQuick
import "Calc.js" as Calc

// Twenty keys, four to a row, in the layout every calculator has had since
// the nineteen-seventies.
//
// A key's colour says what kind of key it is, and there are four kinds: a
// digit is the text on a step up from the window, an operator is the accent
// on a wash of the accent, equals is the accent solid, and clear is the
// theme's red. Nothing carries meaning by colour alone -- every key says what
// it does in a glyph as well. The steps are mixed from the theme's text
// rather than a surface colour: on a light theme a surface is nearly the
// window, and keys mixed from it come out invisible.
Grid {
  id: root
  property var app
  // 62 against the 44 a thumb is usually given. A keypad is the one surface
  // on a phone where a slip costs a wrong number rather than a wrong screen.
  property int keyHeight: 62
  signal pressed(string token)

  columns: Calc.COLUMNS
  spacing: app.compact ? 10 : 8
  readonly property real keyWidth: (width - spacing * (columns - 1)) / columns

  function fill(kind, down) {
    var ui = app.ui
    if (kind === "operator") return Qt.tint(ui.bg, ui.alpha(ui.accent, down ? 0.26 : 0.15))
    if (kind === "equals") return down ? Qt.tint(ui.accent, ui.alpha(ui.text, 0.22)) : ui.accent
    if (kind === "clear") return Qt.tint(ui.bg, ui.alpha(ui.bad, down ? 0.26 : 0.13))
    return Qt.tint(ui.bg, ui.alpha(ui.text, down ? 0.17 : 0.09))
  }

  function ink(kind) {
    var ui = app.ui
    if (kind === "operator") return ui.accent
    if (kind === "equals") return ui.inkOnAccent
    if (kind === "clear") return ui.bad
    // Quieter than a digit, but not a caption's dim: these are controls.
    if (kind === "aux") return Qt.tint(ui.text, ui.alpha(ui.muted, 0.45))
    return ui.text
  }

  function size(key) {
    var body = 15
    if (key.kind === "operator" || key.kind === "equals") return Math.round(body * 1.6)
    // The backspace is a drawn glyph, and at the words' size it reads as a smudge.
    if (key.t === "<") return Math.round(body * 1.4)
    if (key.kind === "aux" || key.kind === "clear") return Math.round(body * 1.15)
    return Math.round(body * 1.45)
  }

  Repeater {
    model: Calc.KEYS
    delegate: Rectangle {
      id: key
      required property var modelData
      width: root.keyWidth
      height: root.keyHeight
      radius: root.app.ui.radius
      color: root.fill(modelData.kind, tap.pressed)
      border.width: 1
      border.color: root.app.ui.line
      Behavior on color { ColorAnimation { duration: 90 } }

      Text {
        anchors.centerIn: parent
        text: key.modelData.label
        color: root.ink(key.modelData.kind)
        font.family: root.app.ui.font
        font.pixelSize: root.size(key.modelData)
        font.weight: key.modelData.kind === "digit" ? Font.Normal : Font.Bold
      }

      MouseArea {
        id: tap
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pressed(key.modelData.t)
      }

      Accessible.role: Accessible.Button
      Accessible.name: modelData.say
      Accessible.onPressAction: root.pressed(modelData.t)
    }
  }
}
