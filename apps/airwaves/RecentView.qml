import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// What you listened to, newest first, kept on this computer.
Item {
  id: root
  property var app
  property bool confirmClear: false

  readonly property var entries: app.store.recent
  readonly property var items: entries.map(function (e) { return e.s })

  function refresh(force) {}

  function ago(t) {
    var s = Math.max(0, (app.clock - t) / 1000)
    if (s < 90) return "Just now"
    if (s < 3600) return Math.round(s / 60) + " min ago"
    if (s < 86400) return Math.round(s / 3600) + " h ago"
    var d = Math.round(s / 86400)
    return d === 1 ? "Yesterday" : d + " days ago"
  }

  Timer { id: confirmTimer; interval: 3000; onTriggered: root.confirmClear = false }

  property alias list: stations

  Component {
    id: top
    Item {
      width: parent ? parent.width : 0
      height: root.items.length ? 44 : 0
      visible: root.items.length > 0
      Text {
        x: stations.pad + 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.items.length + (root.items.length === 1 ? " station" : " stations")
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
      Chip {
        anchors.right: parent.right
        anchors.rightMargin: stations.pad + 10
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        glyph: G.remove
        text: root.confirmClear ? "Tap again to clear" : "Clear history"
        tint: root.app.ui.down
        selected: root.confirmClear
        onClicked: {
          if (!root.confirmClear) { root.confirmClear = true; confirmTimer.restart(); return }
          root.confirmClear = false
          root.app.store.clearRecent()
          root.app.toast("History cleared")
        }
      }
    }
  }

  StationList {
    id: stations
    anchors.fill: parent
    app: root.app
    items: root.items
    topContent: top
    emptyGlyph: G.recent
    emptyTitle: "Nothing played yet"
    emptyDetail: "Stations you listen to show up here."
    emptyAction: "Discover stations"
    onEmptyTriggered: root.app.setTab("discover")
    detailFor: function (s, i) {
      var e = root.entries[i]
      return e ? root.ago(e.t) + (s.country ? " · " + s.country : "") : ""
    }
    onActivated: function (s) { root.app.activate(s) }
  }
}
