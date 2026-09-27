import QtQuick
import "Game.js" as G

// Twenty-eight keys of the app's own, coloured by what is known about each
// letter. The phone has a keyboard already, and using it would slide it up
// over the bottom two rows of a board that is the entire game -- plus
// autocorrect, a space bar and a number row this game has no use for.
Column {
  id: root
  property var app
  // letter -> mark, the best thing known about it.
  property var known: ({})
  property int keyHeight: app.compact ? 52 : 44
  signal letter(string letter)
  signal enter()
  signal back()

  spacing: 6
  readonly property real gap: 4
  readonly property real unit: (width - gap * 9) / 10

  Repeater {
    model: G.KEYBOARD
    delegate: Row {
      id: keyRow
      required property string modelData
      required property int index
      readonly property bool last: index === G.KEYBOARD.length - 1
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: root.gap

      Key {
        visible: keyRow.last
        app: root.app
        label: "ENTER"
        wide: true
        width: root.unit * 1.5 + root.gap / 2
        height: root.keyHeight
        onTapped: root.enter()
      }
      Repeater {
        model: keyRow.modelData.split("")
        delegate: Key {
          required property string modelData
          app: root.app
          label: modelData
          width: root.unit
          height: root.keyHeight
          mark: root.known[modelData] === undefined ? -1 : root.known[modelData]
          onTapped: root.letter(modelData)
        }
      }
      Key {
        visible: keyRow.last
        app: root.app
        label: "DELETE"
        wide: true
        width: root.unit * 1.5 + root.gap / 2
        height: root.keyHeight
        onTapped: root.back()
      }
    }
  }
}
