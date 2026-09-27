import QtQuick

// The score, the best, and the lives left as a row of dots: three of anything
// is faster to read as three shapes than as a digit, and this is glanced at in
// the middle of a rally without taking an eye off the ball.
Item {
  id: root
  property var app

  implicitHeight: 52

  Column {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    Text {
      text: root.app.score
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xl
      font.weight: Font.Bold
      font.features: ({ "tnum": 1 })
    }
    Text {
      text: root.app.saved.stats.best ? "BEST " + root.app.saved.stats.best : "SCORE"
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.weight: Font.DemiBold
      font.letterSpacing: 0.8
    }
  }

  Row {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: 6
    Accessible.role: Accessible.StaticText
    Accessible.name: root.app.lives + " lives left"
    Repeater {
      model: 3
      delegate: Rectangle {
        required property int index
        width: 12
        height: 12
        radius: 6
        color: index < root.app.lives ? root.app.ui.bat : "transparent"
        border.width: 2
        border.color: index < root.app.lives ? root.app.ui.bat : root.app.ui.border
      }
    }
  }
}
