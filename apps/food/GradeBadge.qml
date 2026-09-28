import QtQuick
import "Facts.js" as F

// A letter the size of a thumb, with a caption under it. The letter is on the
// badge as well as the colour, because roughly one man in twelve cannot tell
// the green end of a Nutri-Score from the red.
Column {
  id: root
  property var app
  // "a".."e", or "" for no grade.
  property string grade: ""
  // What to draw instead of a letter: NOVA's number, or a dash.
  property string fallback: F.DASH
  property string caption: ""
  property int size: 56

  spacing: 4

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.size
    height: root.size
    radius: root.app.ui.radius
    color: root.grade ? root.app.ui.gradeFill(root.grade) : root.app.ui.surfaceHigh
    border.width: 1
    border.color: root.grade ? root.app.ui.gradeHue(root.grade) : root.app.ui.line
    Text {
      anchors.centerIn: parent
      text: root.grade ? root.grade.toUpperCase() : root.fallback
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: Math.round(root.size * 0.5)
      font.weight: Font.Bold
    }
  }
  Text {
    visible: root.caption !== ""
    anchors.horizontalCenter: parent.horizontalCenter
    text: root.caption
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: 10
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.6
  }
}
