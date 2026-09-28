import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G

// What you kept: videos saved for later, and what you played, last first.
// Both are copies of the claims in library.json, so they open with no signal.
Item {
  id: root
  property var app
  property string shelf: "saved"
  property int current: -1
  readonly property var items: shelf === "saved" ? app.saved : app.history
  readonly property alias grid: grid

  onShelfChanged: { current = -1; grid.positionViewAtBeginning() }

  Row {
    id: shelves
    x: root.app.ui.gutter
    y: 6
    spacing: 6
    Chip {
      app: root.app
      glyph: G.saved
      text: "Saved" + (root.app.saved.length ? "  " + root.app.saved.length : "")
      selected: root.shelf === "saved"
      onClicked: root.shelf = "saved"
    }
    Chip {
      app: root.app
      glyph: KG.history
      text: "History" + (root.app.history.length ? "  " + root.app.history.length : "")
      selected: root.shelf === "history"
      onClicked: root.shelf = "history"
    }
  }

  Button {
    anchors.right: parent.right
    anchors.rightMargin: root.app.ui.gutter
    anchors.verticalCenter: shelves.verticalCenter
    visible: root.shelf === "history" && root.app.history.length > 0
    app: root.app
    glyph: G.clear
    text: root.app.compact ? "" : "Clear"
    onClicked: root.app.clearHistory()
  }

  VideoGrid {
    id: grid
    anchors.top: shelves.bottom
    anchors.topMargin: 12
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    app: root.app
    items: root.items
    now: root.app.nowSec
    savedIds: root.shelf === "history" ? root.app.savedIds : ({})
    current: root.current
    emptyGlyph: root.shelf === "saved" ? G.save : KG.history
    emptyTitle: root.shelf === "saved" ? "Nothing saved" : "Nothing played yet"
    emptyText: root.shelf === "saved"
      ? "The bookmark on a video keeps it here for later, on this machine."
      : "What you play is listed here, last first. It stays on this machine."
    onOpened: function (item) { root.app.openVideo(item) }
    onChannelOpened: function (ch) { root.app.openChannel(ch) }
  }
}
