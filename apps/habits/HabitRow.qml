import QtQuick
import "Habits.js" as H

// One habit on the Today list: its name, how it is going, and the last few
// days to tick. On a phone the days get a line of their own under the name --
// five 44 px targets beside a name at 360 px leaves the name no room -- and on
// a desktop they sit at the end of the same line, a week of them.
Rectangle {
  id: root
  property var app
  property var habit: null
  property var days: []
  property bool selected: false
  signal opened()

  readonly property bool stacked: app.compact

  implicitHeight: stacked ? 92 : 60
  radius: app.ui.radius
  color: selected ? app.ui.selected : open.pressed ? app.ui.pressed : open.containsMouse ? app.ui.hover : "transparent"
  Accessible.role: Accessible.ListItem
  Accessible.name: habit ? habit.name : ""

  // Declared before the marks, so the marks sit on top and get their taps.
  MouseArea {
    id: open
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened()
  }

  Rectangle {
    id: swatch
    x: 12
    y: root.stacked ? 18 : (parent.height - height) / 2
    width: 10
    height: 10
    radius: 5
    color: root.habit ? root.app.habitHue(root.habit.colour) : "transparent"
  }

  Column {
    anchors.left: swatch.right
    anchors.leftMargin: 10
    anchors.right: root.stacked ? parent.right : marks.left
    anchors.rightMargin: 12
    y: root.stacked ? 10 : (parent.height - height) / 2
    spacing: 2
    Text {
      width: parent.width
      text: root.habit ? (root.habit.name || "Untitled") : ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: root.habit ? root.app.captionFor(root.habit, root.app.revision) : ""
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      elide: Text.ElideRight
    }
  }

  Row {
    id: marks
    anchors.right: parent.right
    anchors.rightMargin: 4
    // A y rather than two anchors swapped by bindings: an anchor bound to
    // `undefined` does not let go, and the marks sat on the caption.
    y: root.stacked ? parent.height - height - 4 : (parent.height - height) / 2
    Repeater {
      model: root.days
      delegate: DayMark {
        id: mark
        required property var modelData
        app: root.app
        habit: root.habit
        day: modelData
        isToday: modelData === root.app.today
        onTapped: if (root.app.tick(root.habit, modelData)) mark.celebrate()
      }
    }
  }
}
