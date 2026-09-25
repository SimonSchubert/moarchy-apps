import QtQuick
import "Glyphs.js" as G

// Your rating, 1 to 10, as ten stars. Tap one to rate; tap your rating again
// to take it back.
Item {
  id: root
  property var app
  property int value: 0
  property int hover: 0
  signal rated(int value)

  readonly property var words: ["", "Weak sauce", "Terrible", "Bad", "Poor", "Meh", "Fair", "Good", "Great", "Superb", "Totally ninja!"]
  readonly property int star: app.compact ? 24 : 22
  readonly property int shown: hover || value

  // Stars, and the word for the rating beside them -- or under them, where
  // there is no room beside.
  readonly property bool stacked: width > 0 && width < stars.width + 12 + label.implicitWidth
  implicitWidth: stars.width + 12 + label.implicitWidth
  implicitHeight: stacked ? stars.height + label.implicitHeight + 2 : star + 8

  Row {
    id: stars
    spacing: 1
    Repeater {
      model: 10
      delegate: Item {
        id: cell
        required property int index
        width: root.star
        height: root.star + 8
        Accessible.role: Accessible.Button
        Accessible.name: "Rate " + (index + 1) + " of 10"
        Icon {
          anchors.centerIn: parent
          app: root.app
          text: cell.index < root.shown ? G.star : G.starOutline
          size: root.star - 4
          width: root.star
          color: cell.index < root.shown ? root.app.ui.star : root.app.alpha(root.app.ui.text, 0.3)
          scale: starMouse.pressed ? 0.8 : 1
          Behavior on scale { NumberAnimation { duration: 90 } }
        }
        MouseArea {
          id: starMouse
          anchors.fill: parent
          hoverEnabled: !root.app.compact
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: root.hover = containsMouse ? cell.index + 1 : (root.hover === cell.index + 1 ? 0 : root.hover)
          onClicked: root.rated(root.value === cell.index + 1 ? 0 : cell.index + 1)
        }
      }
    }
  }
  Text {
    id: label
    x: root.stacked ? 4 : stars.width + 12
    y: root.stacked ? stars.height + 2 : (stars.height - height) / 2
    text: root.shown ? root.shown + "  ·  " + root.words[root.shown] : "Tap to rate"
    color: root.shown ? root.app.ui.text : root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
    font.weight: root.shown ? Font.DemiBold : Font.Normal
  }
}
