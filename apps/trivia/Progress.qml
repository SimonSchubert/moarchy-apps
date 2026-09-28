import QtQuick
import "Trivia.js" as T

// A round as a row of squares: green for right, red for wrong, the accent for
// the one on the screen, and a well for the ones to come. The score screen
// draws the same row finished, so the round reads the same in both.
Row {
  id: root
  property var app
  property var round: null
  property int size: 8
  readonly property int count: round ? round.questions.length : 0

  spacing: count > 15 ? 3 : 4
  height: size

  Repeater {
    model: root.count
    delegate: Rectangle {
      required property int index
      readonly property bool done: index < root.round.picks.length
      width: Math.max(4, (root.width - root.spacing * (root.count - 1)) / Math.max(1, root.count))
      height: root.size
      radius: root.app.ui.radius > 0 ? root.size / 2 : 0
      color: done ? (T.isRight(root.round, index) ? root.app.ui.good : root.app.ui.bad)
        : index === root.round.index ? root.app.ui.accent : root.app.ui.well
      Behavior on color { ColorAnimation { duration: 140 } }
    }
  }
}
