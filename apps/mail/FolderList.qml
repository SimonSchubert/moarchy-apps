import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G

// The folders, as the server named them, with what is unread in each. A page
// on a phone, a column beside the folder on a desktop. Unread in Junk and
// Trash is not waiting for anybody, so it is counted without the accent.
Item {
  id: root
  property var app
  property bool paged: false

  PageHeader {
    id: head
    visible: root.paged
    height: visible ? implicitHeight : 0
    width: parent.width
    app: root.app
    title: "Folders"
    subtitle: root.app.account ? root.app.account.email : ""
    IconButton {
      app: root.app
      glyph: KG.refresh
      label: "Refresh the folders"
      active: root.app.foldersBusy
      onClicked: root.app.refreshFolders()
    }
  }

  EmptyState {
    anchors.horizontalCenter: parent.horizontalCenter
    y: head.height + 40
    visible: root.app.folders.length === 0
    app: root.app
    busy: root.app.foldersBusy
    glyph: G.folder
    title: root.app.foldersBusy ? "Asking for the folders" : "No folders yet"
    text: root.app.foldersBusy ? "" : "Refresh to ask the server again."
  }

  ListView {
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.paged ? root.app.ui.gutter : 0
    anchors.rightMargin: root.paged ? root.app.ui.gutter : 0
    anchors.bottomMargin: root.app.bottomInset
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    spacing: 2
    model: root.app.folders

    delegate: ListRow {
      id: folderRow
      required property var modelData
      readonly property bool quiet: modelData.role === "junk" || modelData.role === "trash"
      width: ListView.view ? ListView.view.width : 0
      app: root.app
      glyph: G.forRole(modelData.role)
      glyphColor: selected ? root.app.ui.accent : root.app.ui.muted
      title: modelData.label
      text: modelData.parent || ""
      selected: modelData.name === root.app.folder
      onClicked: root.app.openFolder(folderRow.modelData.name)

      Rectangle {
        visible: folderRow.modelData.unseen > 0
        width: Math.max(22, count.implicitWidth + 12)
        height: 22
        radius: root.app.ui.round(height)
        color: folderRow.quiet ? root.app.ui.surfaceHigh : root.app.ui.accent
        Text {
          id: count
          anchors.centerIn: parent
          text: String(folderRow.modelData.unseen)
          color: folderRow.quiet ? root.app.ui.text : root.app.ui.inkOnAccent
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          font.weight: Font.Bold
        }
      }
    }
  }
}
