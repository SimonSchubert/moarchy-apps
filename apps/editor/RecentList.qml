import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Doc.js" as Doc
import "Glyphs.js" as G

// The files this has opened, newest first: the whole first screen on a phone,
// the column beside the text on a desktop. A cross takes a row off the list,
// not the file off the disk -- deleting is Files' job, and a cross that
// deleted would be a trap.
Flickable {
  id: root
  property var app
  property var recent: []
  property string home: ""
  property real now: 0
  // The file on the other side of the window, on a desktop.
  property string current: ""
  signal picked(string path)
  signal forgot(string path)

  contentWidth: width
  contentHeight: col.implicitHeight + 96
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  EmptyState {
    visible: root.recent.length === 0
    app: root.app
    anchors.horizontalCenter: parent.horizontalCenter
    y: 60
    glyph: G.file
    title: "No files yet"
    text: "Start a new one, or open a text file from Files."
  }

  Column {
    id: col
    visible: root.recent.length > 0
    x: root.app.ui.gutter
    y: 4
    width: root.width - root.app.ui.gutter * 2
    spacing: 8

    Text {
      text: "Recent"
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.weight: Font.Bold
      font.capitalization: Font.AllUppercase
      font.letterSpacing: root.app.ui.tracking
    }

    Rectangle {
      width: parent.width
      height: rows.implicitHeight + 8
      radius: root.app.ui.radius
      color: root.app.ui.surface
      border.width: 1
      border.color: root.app.ui.line

      Column {
        id: rows
        x: 4
        y: 4
        width: parent.width - 8
        Repeater {
          model: root.recent
          delegate: ListRow {
            id: row
            required property var modelData
            app: root.app
            width: rows.width
            glyph: G.file
            title: Doc.basename(row.modelData.path)
            text: {
              var where = Doc.tilde(Doc.dirname(row.modelData.path), root.home)
              var when = Doc.ago(row.modelData.opened, root.now)
              return when.length ? where + " · " + when : where
            }
            selected: !root.app.compact && root.current === row.modelData.path
            onClicked: root.picked(row.modelData.path)
            IconButton {
              app: root.app
              glyph: KG.close
              size: 15
              label: "Remove from this list"
              implicitWidth: 34
              implicitHeight: 34
              color: root.app.ui.muted
              onClicked: root.forgot(row.modelData.path)
            }
          }
        }
      }
    }
  }
}
