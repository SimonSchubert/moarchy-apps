import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G

// Five stars: a rating to read, to the nearest half, or -- `interactive` --
// your own, one tap a star, the same star again to take it back.
Row {
  id: root
  property var app
  property real value: 0
  property int size: 14
  property bool interactive: false
  property color color: app.ui.warn
  signal picked(int stars)

  spacing: interactive ? 2 : 1
  Accessible.name: value > 0 ? value.toFixed(1) + " of 5 stars" : "Not rated"

  Repeater {
    model: 5
    delegate: Item {
      id: star
      required property int index
      readonly property real fill: Math.max(0, Math.min(1, root.value - index))
      width: root.interactive ? Math.max(root.size + 8, root.app.ui.target - 6) : root.size + 1
      height: root.interactive ? width : root.size + 2
      Icon {
        anchors.centerIn: parent
        app: root.app
        size: root.size
        text: star.fill >= 0.75 ? KG.star : star.fill >= 0.25 ? G.starHalf : KG.starOutline
        color: star.fill >= 0.25 ? root.color : root.app.ui.alpha(root.app.ui.muted, root.interactive ? 0.8 : 0.55)
      }
      MouseArea {
        anchors.fill: parent
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked(star.index + 1)
      }
    }
  }
}
