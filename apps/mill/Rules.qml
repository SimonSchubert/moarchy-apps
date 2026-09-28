import QtQuick
import "kit"

// The rules, in five lines, including the one everybody forgets.
Card {
  id: root
  title: "How it is played"
  readonly property var lines: [
    ["Place", "Nine pieces each, one a turn, on any empty point."],
    ["Mill", "Three in a line takes one of the other side's pieces — not one in a mill, unless every one of them is."],
    ["Move", "With the hand empty, slide a piece along a line to the next point."],
    ["Fly", "Down to three, a side may move a piece to any empty point."],
    ["End", "Two pieces left, or no move to make, is a loss. Fifty moves with nothing taken is a draw."]
  ]
  Repeater {
    model: root.lines
    delegate: Row {
      required property var modelData
      width: parent.width
      spacing: 10
      Text {
        width: 52
        text: modelData[0]
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
        font.weight: Font.Bold
      }
      Text {
        width: parent.width - 62
        wrapMode: Text.Wrap
        text: modelData[1]
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
    }
  }
}
