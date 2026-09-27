import QtQuick

// A titled group on the settings screen; its controls follow the note.
Column {
  id: section
  property var app
  property string title: ""
  property string note: ""
  spacing: 8

  Text {
    text: section.title
    color: section.app.ui.text
    font.family: section.app.ui.font
    font.pixelSize: section.app.ui.fs.md
    font.weight: Font.DemiBold
  }
  Text {
    visible: section.note !== ""
    width: section.width
    wrapMode: Text.Wrap
    text: section.note
    color: section.app.ui.muted
    font.family: section.app.ui.font
    font.pixelSize: section.app.ui.fs.xs
  }
}
