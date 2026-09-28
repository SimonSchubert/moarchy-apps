import QtQuick
import "kit"
import "Sysinfo.js" as Sysinfo
import "Glyphs.js" as G

// What is running. Apps by default -- one row for a browser's twenty
// processes, adding up to what the browser costs -- and every process when the
// answer really is a particular pid. Sorted by processor, memory or name, and
// searched by name, command line or pid.
//
// On a desktop wide enough, what is picked opens beside the list rather than
// over it, so the list keeps its place while you look.
Item {
  id: root
  property var app

  readonly property var s: app.sample
  readonly property string mode: app.store.prefs.taskMode
  readonly property string sort: app.store.prefs.taskSort
  readonly property alias query: search.text
  readonly property bool wide: !app.compact && list.width >= 560
  readonly property bool side: app.splitTasks && app.selection !== null

  readonly property var rows: {
    if (!s) return []
    var src = mode === "all" ? s.processes : s.apps
    var q = query.trim().toLowerCase()
    var out = []
    for (var i = 0; i < src.length; i++) {
      var r = src[i]
      if (q) {
        var hit = r.name.toLowerCase().indexOf(q) >= 0
          || (r.cmdline && r.cmdline.toLowerCase().indexOf(q) >= 0)
          || (r.pid !== undefined && String(r.pid) === q)
          || (r.pids !== undefined && r.pids.indexOf(parseInt(q, 10)) >= 0)
        if (!hit) continue
      }
      out.push(mode === "all" ? Object.assign({ key: "p" + r.pid }, r) : r)
    }
    var by = sort
    out.sort(function (a, b) {
      if (by === "memory") return (b.rss - a.rss) || (b.cpu - a.cpu) || (a.name < b.name ? -1 : 1)
      if (by === "name") {
        var an = a.name.toLowerCase(), bn = b.name.toLowerCase()
        return an < bn ? -1 : an > bn ? 1 : ((a.pid || 0) - (b.pid || 0))
      }
      return (b.cpu - a.cpu) || (b.rss - a.rss) || (a.name < b.name ? -1 : 1)
    })
    return out
  }

  Keyed { id: keyed; items: root.rows }

  function selOf(item) {
    if (!item) return null
    return item.pids !== undefined ? { kind: "app", key: item.key } : { kind: "process", pid: item.pid }
  }
  function isSelected(item) {
    var sel = root.app.shownSel
    if (!sel || !item) return false
    return sel.kind === "app" ? item.key === sel.key : item.pid === sel.pid && item.pids === undefined
  }

  function move(step) {
    if (!list.count) return
    var i = list.currentIndex < 0 ? (step > 0 ? 0 : list.count - 1) : list.currentIndex + step
    list.currentIndex = Math.max(0, Math.min(list.count - 1, i))
    list.positionViewAtIndex(list.currentIndex, ListView.Contain)
    if (root.side) root.app.selection = selOf(keyed.at(keyed.order[list.currentIndex]))
  }
  function currentSel() {
    if (list.currentIndex < 0 || list.currentIndex >= keyed.order.length) return null
    return selOf(keyed.at(keyed.order[list.currentIndex]))
  }
  function activateCurrent() { var sel = currentSel(); if (sel) root.app.openDetail(sel) }
  function focusField() { search.input.forceActiveFocus() }
  function clearQuery() { search.text = "" }

  onModeChanged: list.currentIndex = -1

  // ------------------------------------------------------------ toolbar

  Column {
    id: bar
    x: root.app.ui.gutter
    y: root.app.compact ? 0 : 4
    width: (root.side ? pane.x : parent.width) - root.app.ui.gutter * 2
    spacing: 10

    // Narrow: search on its own line, the choices under it. Wide: one line.
    Flow {
      width: parent.width
      spacing: 8

      SearchField {
        id: search
        app: root.app
        width: root.app.compact ? bar.width : Math.min(320, bar.width - choices.implicitWidth - 16)
        placeholder: root.mode === "all" ? "Search processes, commands, pids" : "Search apps"
        onEscaped: root.app.resetFocus()
      }

      Row {
        id: choices
        spacing: 6
        Chip { app: root.app; text: "Apps"; glyph: G.app; selected: root.mode === "apps"; onClicked: root.app.store.set("taskMode", "apps") }
        Chip { app: root.app; text: "All"; glyph: G.tree; selected: root.mode === "all"; onClicked: root.app.store.set("taskMode", "all") }
        Rectangle { width: 1; height: root.app.ui.chip - 10; anchors.verticalCenter: parent.verticalCenter; color: root.app.ui.line }
        Repeater {
          model: [
            { key: "cpu", label: root.app.compact ? "CPU" : "Processor" },
            { key: "memory", label: "Memory" },
            { key: "name", label: "Name" }
          ]
          delegate: Chip {
            required property var modelData
            app: root.app
            hpad: 18
            text: modelData.label
            selected: root.sort === modelData.key
            onClicked: root.app.store.set("taskSort", modelData.key)
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ list

  Item {
    id: listBox
    anchors.top: bar.bottom
    anchors.topMargin: 10
    anchors.left: parent.left
    anchors.right: root.side ? pane.left : parent.right
    anchors.bottom: parent.bottom

    // Column names, on a desktop, which are also the way to sort by them.
    Item {
      id: head
      visible: root.wide
      x: root.app.ui.gutter
      width: parent.width - root.app.ui.gutter * 2
      height: visible ? 28 : 0

      Text {
        x: 38
        anchors.verticalCenter: parent.verticalCenter
        text: (root.mode === "all" ? "Process" : "App") + (root.sort === "name" ? "  ↓" : "")
        color: root.sort === "name" ? root.app.ui.text : root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: root.app.ui.tracking
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.app.store.set("taskSort", "name") }
      }
      Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16
        Repeater {
          model: [
            { key: "cpu", label: "Processor", w: root.app.colCpu },
            { key: "memory", label: "Memory", w: root.app.colMem },
            { key: "", label: root.mode === "all" ? "Threads" : "Procs", w: root.app.colCount }
          ]
          delegate: Text {
            required property var modelData
            width: modelData.w
            horizontalAlignment: Text.AlignRight
            text: modelData.label + (root.sort === modelData.key ? "  ↓" : "")
            color: root.sort === modelData.key ? root.app.ui.text : root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: root.app.ui.tracking
            MouseArea {
              anchors.fill: parent
              enabled: modelData.key !== ""
              cursorShape: Qt.PointingHandCursor
              onClicked: root.app.store.set("taskSort", modelData.key)
            }
          }
        }
      }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.app.ui.line }
    }

    ListView {
      id: list
      anchors.top: head.bottom
      anchors.topMargin: 4
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: root.app.ui.gutter - 6
      anchors.rightMargin: root.app.ui.gutter - 6
      clip: true
      model: keyed
      currentIndex: -1
      boundsBehavior: Flickable.StopAtBounds
      reuseItems: true

      delegate: TaskRow {
        required property string key
        required property int index
        app: root.app
        width: ListView.view.width
        item: keyed.at(key)
        wide: root.wide
        figure: root.sort === "memory" ? "memory" : "cpu"
        selected: root.isSelected(item)
        current: ListView.isCurrentItem && !root.app.compact
        onClicked: {
          list.currentIndex = index
          root.app.openDetail(root.selOf(item))
        }
      }

      footer: Item { width: 1; height: 16 }
    }

    Text {
      anchors.centerIn: parent
      width: parent.width - 48
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      visible: root.s !== null && root.rows.length === 0
      text: root.s && root.s.processes.length === 0 ? "Reading processes…"
        : "Nothing matches “" + root.query.trim() + "”"
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
    }
  }

  // ------------------------------------------------------------ side pane

  Rectangle {
    id: pane
    visible: root.side
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    width: visible ? Math.min(420, Math.max(340, parent.width * 0.38)) : 0
    color: root.app.ui.surface
    Rectangle { width: 1; height: parent.height; color: root.app.ui.line }

    DetailView {
      anchors.fill: parent
      anchors.leftMargin: 1
      app: root.app
      sel: root.app.selection
      paged: false
    }
  }
}
