import QtQuick
import "kit"

// The game written down, a move number and two plies a line, the latest one
// lit. On a desktop only: it is what the extra width is for, and on a phone
// the board is the whole screen.
Card {
  id: root
  property var sans: []

  title: "Moves"
  trailing: sans.length ? Math.ceil(sans.length / 2) + "" : ""

  readonly property var lines: {
    var out = []
    for (var i = 0; i < sans.length; i += 2) out.push({ n: i / 2 + 1, w: sans[i], b: i + 1 < sans.length ? sans[i + 1] : "" })
    return out
  }

  Text {
    visible: root.sans.length === 0
    text: "No moves yet"
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }

  Grid {
    visible: root.sans.length > 0
    width: parent.width
    columns: 2
    columnSpacing: 12
    rowSpacing: 4
    flow: Grid.TopToBottom
    rows: Math.ceil(root.lines.length / 2)
    Repeater {
      model: root.lines
      delegate: Row {
        id: line
        required property var modelData
        required property int index
        spacing: 6
        width: (root.width - root.pad * 2 - 12) / 2
        readonly property bool latest: index === root.lines.length - 1
        Text {
          width: 26
          text: line.modelData.n + "."
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.features: ({ "tnum": 1 })
        }
        Text {
          width: (line.width - 38) / 2
          text: line.modelData.w
          color: line.latest && !line.modelData.b ? root.app.ui.accent : root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: line.latest && !line.modelData.b ? Font.Bold : Font.Normal
        }
        Text {
          width: (line.width - 38) / 2
          text: line.modelData.b
          color: line.latest && line.modelData.b ? root.app.ui.accent : root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: line.latest && line.modelData.b ? Font.Bold : Font.Normal
        }
      }
    }
  }
}
