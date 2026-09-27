import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G

// One line of a checklist in the editor: its tick box, its text, and a way to
// remove it. Enter makes the next line; Backspace in an empty line removes it
// and goes back to the one before -- a list gets long by accident, and a small
// delete button for every stray line is the slow way out.
Row {
  id: row
  required property var modelData
  property var editor
  readonly property int index: modelData.index
  readonly property var item: editor.draft ? editor.draft.items[index] : ({ text: "", done: false })

  width: parent ? parent.width : 300
  spacing: 4

  Component.onCompleted: if (editor.focusItem === index) {
    input.forceActiveFocus()
    input.cursorPosition = input.text.length
    editor.focusItem = -1
  }

  IconButton {
    anchors.verticalCenter: parent.verticalCenter
    app: row.editor.app
    glyph: row.item.done ? G.checked : G.unchecked
    label: row.item.done ? "Untick" : "Tick"
    color: row.editor.app.ui.muted
    onClicked: row.editor.tick(row.index)
  }

  TextInput {
    id: input
    anchors.verticalCenter: parent.verticalCenter
    width: row.width - row.editor.app.ui.target * 2 - 8
    text: row.item.text
    color: row.item.done ? row.editor.app.ui.muted : row.editor.app.ui.text
    selectionColor: row.editor.app.ui.accent
    selectedTextColor: row.editor.app.ui.inkOnAccent
    font.family: row.editor.app.ui.font
    font.pixelSize: row.editor.app.ui.fs.md + 1
    font.strikeout: row.item.done
    clip: true
    onTextChanged: if (row.editor.draft && text !== row.item.text) { row.editor.draft.items[row.index].text = text; row.editor.touched() }
    Keys.onReturnPressed: row.editor.addItem(row.index)
    Keys.onEnterPressed: row.editor.addItem(row.index)
    Keys.onPressed: function (event) {
      if (event.key === Qt.Key_Backspace && text === "" && row.editor.draft.items.length > 1) {
        row.editor.removeItem(row.index, true)
        event.accepted = true
      }
    }
  }

  IconButton {
    anchors.verticalCenter: parent.verticalCenter
    app: row.editor.app
    glyph: KG.close
    size: 16
    label: "Remove item"
    color: row.editor.app.ui.muted
    onClicked: row.editor.removeItem(row.index, false)
  }
}
