import QtQuick

// A labelled one-line text field. `label` is optional; without it the field
// is just the box. Focus comes from a press, never from the field appearing, so the phone's keyboard comes up because somebody asked
// for it; Escape and Enter hand the keys back to the window.
Column {
  id: root
  property var app
  property string label: ""
  property alias text: input.text
  property string placeholder: ""
  property int inputHints: Qt.ImhNone
  property alias input: input
  property alias echoMode: input.echoMode
  property alias readOnly: input.readOnly
  signal accepted()
  function takeFocus() { input.forceActiveFocus() }

  spacing: 6

  Text {
    visible: root.label !== ""
    text: root.label
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
    font.weight: Font.Bold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: root.app.ui.tracking
  }

  Rectangle {
    width: parent.width
    height: root.app.compact ? 44 : 38
    radius: root.app.ui.radius
    color: root.app.ui.surface
    border.width: 1
    border.color: input.activeFocus ? root.app.ui.accent : root.app.ui.line

    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: 12
      anchors.rightMargin: 12
      verticalAlignment: TextInput.AlignVCenter
      color: root.app.ui.text
      selectionColor: root.app.ui.accent
      selectedTextColor: root.app.ui.inkOnAccent
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      clip: true
      activeFocusOnPress: true
      inputMethodHints: root.inputHints
      Keys.onEscapePressed: function (event) { root.app.resetFocus(); event.accepted = true }
      Keys.onReturnPressed: function (event) { root.accepted(); event.accepted = true }
      Keys.onEnterPressed: function (event) { root.accepted(); event.accepted = true }

      Text {
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        visible: !input.text && !input.activeFocus
        text: root.placeholder
        color: root.app.ui.muted
        font: input.font
        elide: Text.ElideRight
      }
    }
  }
}
