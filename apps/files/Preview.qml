import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Listing.js" as Listing
import "Path.js" as Path

// The picked row, beside the list on a desktop: what it is, and every thing
// that can be done to it as a button rather than a menu, because a desktop
// has the room.
Rectangle {
  id: root
  property var app
  property var entry: null
  property string dir: ""
  property real now: 0
  property bool inTrash: false
  signal close()

  color: app.ui.surface
  radius: app.ui.radius
  border.width: 1
  border.color: app.ui.line

  readonly property string kind: {
    if (!entry) return ""
    if (entry.broken) return "A link to nothing"
    if (entry.folder) return entry.link ? "Folder link" : "Folder"
    var k = Listing.kindOf(entry.name)
    var what = k ? k.charAt(0).toUpperCase() + k.slice(1) : "File"
    return (entry.link ? "Link · " : "") + what + " · " + Listing.human(entry.size)
  }

  function stamp(seconds) {
    if (!(seconds > 0)) return ""
    var d = new Date(seconds * 1000)
    return d.toLocaleDateString(Qt.locale(), Locale.LongFormat) + ", " + d.toLocaleTimeString(Qt.locale(), "HH:mm")
  }

  IconButton {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 6
    app: root.app
    glyph: KG.close
    label: "Close"
    onClicked: root.close()
  }

  Column {
    x: 20
    y: 24
    width: parent.width - 40
    spacing: 14

    Icon {
      app: root.app
      text: root.entry ? G.of(Listing.glyphs(root.entry)) : ""
      size: 44
      color: root.entry && root.entry.folder ? root.app.ui.accent : root.app.ui.muted
    }
    Text {
      width: parent.width
      text: root.entry ? root.entry.name : ""
      wrapMode: Text.WrapAnywhere
      maximumLineCount: 4
      elide: Text.ElideRight
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.lg
      font.weight: Font.Bold
    }
    Column {
      width: parent.width
      spacing: 10
      Repeater {
        model: [
          ["What", root.kind],
          ["Changed", root.entry ? root.stamp(root.entry.modified) : ""],
          ["Where", Path.pretty(root.dir, root.app.home)]
        ]
        delegate: Column {
          required property var modelData
          width: parent.width
          spacing: 2
          visible: modelData[1] !== ""
          Text {
            text: modelData[0]
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
            font.capitalization: Font.AllUppercase
            font.letterSpacing: root.app.ui.tracking
          }
          Text {
            width: parent.width
            text: modelData[1]
            wrapMode: Text.WrapAnywhere
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
        }
      }
    }
    Flow {
      width: parent.width
      spacing: 8
      Button {
        app: root.app
        primary: true
        glyph: root.entry && root.entry.folder ? G.folder : G.open
        text: root.entry && root.entry.folder ? "Open folder" : "Open"
        onClicked: root.app.enter(root.entry)
      }
      Button { app: root.app; glyph: G.copy; text: "Copy"; onClicked: root.app.hold("copy", root.entry) }
      Button { app: root.app; glyph: G.cut; text: "Move"; onClicked: root.app.hold("move", root.entry) }
      Button { app: root.app; glyph: G.rename; text: "Rename"; onClicked: root.app.askRename(root.entry) }
      Button {
        app: root.app
        glyph: root.inTrash ? G.purge : G.trash
        tint: root.app.ui.bad
        active: true
        text: root.inTrash ? "Delete for ever" : "Move to trash"
        onClicked: root.app.remove(root.entry)
      }
    }
  }
}
