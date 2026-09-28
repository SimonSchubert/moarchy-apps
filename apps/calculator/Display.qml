import QtQuick

// The sum, and under it the running answer, in a box. Right-aligned and elided
// at the left, which is the end a long sum is not being typed at: what stays
// on screen is the part still being written.
Rectangle {
  id: root
  property var app
  property string sum: "0"
  property string answer: ""
  property bool problem: false
  property int sumSize: 36

  implicitHeight: sumText.implicitHeight + answerText.implicitHeight + 30
  radius: app.ui.radius
  color: app.ui.surface
  border.width: 1
  border.color: app.ui.line

  Text {
    id: sumText
    anchors.bottom: answerText.top
    anchors.bottomMargin: 2
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: 16
    anchors.rightMargin: 16
    text: root.sum
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.sumSize
    font.features: ({ "tnum": 1 })
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideLeft
    maximumLineCount: 1
  }

  Text {
    id: answerText
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 14
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: 16
    anchors.rightMargin: 16
    // A line kept even when empty, so the sum does not jump as it appears.
    text: root.answer !== "" ? root.answer : " "
    color: root.problem ? root.app.ui.bad : root.app.ui.accent
    font.family: root.app.ui.font
    font.pixelSize: Math.round(root.sumSize * 0.56)
    font.features: ({ "tnum": 1 })
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideLeft
    maximumLineCount: 1
  }
}
