import QtQuick

// A labelled one-line input. Focus only when pressed, so the phone's keyboard
// comes up because somebody asked for it.
Column {
  id: root
  property var app
  property string label: ""
  property string suffix: ""
  property string placeholder: ""
  property alias text: input.text
  property alias input: input
  property bool numeric: true
  property bool valid: true
  signal edited(string value)
  signal accepted()

  spacing: 4

  Text {
    visible: root.label !== ""
    text: root.label
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
  }

  Rectangle {
    width: parent.width
    height: 44
    radius: root.app.ui.radius
    color: root.app.ui.bg
    border.width: 1
    border.color: !root.valid ? root.app.ui.down : input.activeFocus ? root.app.ui.accent : root.app.ui.border

    TextInput {
      id: input
      anchors.left: parent.left
      anchors.leftMargin: 12
      anchors.right: suffixText.left
      anchors.rightMargin: 8
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      verticalAlignment: TextInput.AlignVCenter
      color: root.app.ui.text
      selectionColor: root.app.ui.accent
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.features: ({ "tnum": 1 })
      clip: true
      inputMethodHints: root.numeric ? Qt.ImhFormattedNumbersOnly : Qt.ImhNoPredictiveText
      onTextEdited: root.edited(text)
      onAccepted: root.accepted()

      Text {
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        visible: !input.text
        text: root.placeholder
        color: root.app.ui.muted
        font: input.font
      }
    }
    Text {
      id: suffixText
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      text: root.suffix
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.weight: Font.DemiBold
    }
  }
}
