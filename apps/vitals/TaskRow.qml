import QtQuick
import "kit"
import "Sysinfo.js" as Sysinfo
import "Glyphs.js" as G

// One app or one process in a list.
//
// Narrow, it is a name with a line under it and the one figure the list is
// about on the right. Wide -- the task list on a desktop -- it is a table row:
// processor with a bar, memory, and how many processes or which pid, in
// columns that line up down the page.
//
// `item` is either shape Sysinfo makes: an app ({ key, name, kernel, pids,
// cpu, rss }) or a process ({ pid, name, state, rss, cpu, cmdline, kernel }).
Rectangle {
  id: root
  property var app
  property var item: ({})
  property bool wide: false
  property bool selected: false
  property bool current: false
  // What the figure on the right is, narrow: "cpu" or "memory".
  property string figure: "cpu"
  signal clicked()

  readonly property bool isApp: item.pids !== undefined
  readonly property bool quiet: !!item.kernel

  implicitHeight: app.compact ? 58 : 52
  radius: app.ui.radius
  color: selected ? app.ui.selected : mouse.pressed ? app.ui.pressed
    : (current || mouse.containsMouse) ? app.ui.hover : "transparent"

  function subtitle() {
    var it = root.item
    if (!it || it.name === undefined) return ""
    if (root.isApp) {
      if (it.kernel) return it.pids.length + " threads"
      var n = it.pids.length > 1 ? it.pids.length + " processes" : "pid " + it.pids[0]
      if (root.wide) return n
      return n + " · " + (root.figure === "cpu" ? Sysinfo.humanBytes(it.rss) : Sysinfo.taskPercent(it.cpu) + " processor")
    }
    var bits = ["pid " + it.pid, it.state]
    if (!root.wide) bits.push(root.figure === "cpu" ? Sysinfo.humanBytes(it.rss) : Sysinfo.taskPercent(it.cpu))
    return bits.join(" · ")
  }

  Icon {
    id: glyph
    x: 8
    anchors.verticalCenter: parent.verticalCenter
    app: root.app
    size: 18
    text: root.quiet ? G.kernel : root.isApp ? G.app : G.pulse
    color: root.selected ? root.app.ui.accent : root.app.ui.muted
  }

  Column {
    anchors.left: glyph.right
    anchors.leftMargin: 6
    anchors.right: root.wide ? cols.left : figureText.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2
    Text {
      width: parent.width
      text: root.item.name || ""
      color: root.quiet ? root.app.ui.muted : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.Bold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: root.subtitle()
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.features: ({ "tnum": 1 })
      elide: Text.ElideRight
    }
  }

  // Narrow: one figure.
  Text {
    id: figureText
    visible: !root.wide
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    text: root.figure === "cpu" ? Sysinfo.taskPercent(root.item.cpu || 0) : Sysinfo.humanBytes(root.item.rss || 0)
    color: root.figure === "cpu" ? root.app.loadColor(root.item.cpu || 0) : root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.md
    font.weight: Font.Bold
    font.features: ({ "tnum": 1 })
  }

  // Wide: the columns TaskHeader names.
  Row {
    id: cols
    visible: root.wide
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 16

    Item {
      width: root.app.colCpu
      height: 32
      Text {
        anchors.right: parent.right
        y: 1
        text: Sysinfo.taskPercent(root.item.cpu || 0)
        color: root.app.loadColor(root.item.cpu || 0)
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
        font.weight: Font.Bold
        font.features: ({ "tnum": 1 })
      }
      Meter {
        app: root.app
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: parent.width
        implicitHeight: 4
        // A share of the machine is small, so the bar is drawn against a
        // quarter of it: one busy core of four fills it.
        value: Math.min(1, (root.item.cpu || 0) * 4)
        fill: root.app.loadColor(root.item.cpu || 0)
      }
    }
    Text {
      width: root.app.colMem
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      text: Sysinfo.humanBytes(root.item.rss || 0)
      color: root.quiet ? root.app.ui.muted : root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.features: ({ "tnum": 1 })
    }
    Text {
      width: root.app.colCount
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      text: root.isApp ? String(root.item.pids ? root.item.pids.length : 0) : (root.item.threads || 1) + ""
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.features: ({ "tnum": 1 })
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
