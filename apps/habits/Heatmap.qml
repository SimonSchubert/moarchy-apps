import QtQuick
import "Habits.js" as H

// Sixteen weeks of one habit, weekdays down and weeks across, ending with
// this one. The shape people already know from contribution graphs, which is
// worth more than a prettier idea: nobody has to be told how to read it.
Row {
  id: root
  property var app
  property var habit: null
  property int weeks: 16
  // The cell's side, from the width there is; never bigger than reads well.
  property real cell: 15

  spacing: 5
  readonly property var grid: H.historyGrid(app.today, weeks)

  Column {
    spacing: 3
    Repeater {
      model: H.WEEKDAYS
      delegate: Text {
        required property var modelData
        required property int index
        width: 12
        height: root.cell
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignRight
        text: index % 2 === 0 ? modelData : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: Math.min(root.app.ui.fs.xs, root.cell)
      }
    }
  }

  Row {
    spacing: 3
    Repeater {
      model: root.grid
      delegate: Column {
        id: week
        required property var modelData
        spacing: 3
        Repeater {
          model: week.modelData
          delegate: Rectangle {
            required property var modelData
            width: root.cell
            height: root.cell
            radius: root.app.ui.radius > 0 ? Math.max(2, Math.round(root.cell * 0.25)) : 0
            // A day that has not happened yet is left out, not marked missed.
            color: modelData === null ? "transparent"
              : root.habit ? root.app.markColour(root.habit, modelData, root.app.revision) : "transparent"
            border.width: modelData === root.app.today ? 1 : 0
            border.color: root.app.ui.accent
          }
        }
      }
    }
  }
}
