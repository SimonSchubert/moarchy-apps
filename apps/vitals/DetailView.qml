import QtQuick
import "kit"
import "Sysinfo.js" as Sysinfo
import "Glyphs.js" as G

// One app or one process, looked at: what it costs, what it is, and the two
// ways of stopping it -- which are two different signals, and say so.
//
// `paged` is a page of its own on a phone, with a back arrow; otherwise it is
// the pane beside the task list, with a close button.
Item {
  id: root
  property var app
  property var sel: null
  property bool paged: false

  readonly property var s: app.sample
  readonly property bool isApp: sel !== null && sel.kind === "app"
  readonly property var item: {
    if (!sel || !s) return null
    return isApp ? app.findApp(sel.key) : app.findProcess(sel.pid)
  }
  readonly property var procs: isApp ? app.processesOf(item) : []
  readonly property var parentProc: !isApp && item ? app.findProcess(item.ppid) : null

  // The processor over the time this has been open, so a spike can be seen
  // for what it is. Starts again when the selection changes.
  property var cpuHist: []
  property var lastSample: null
  onSelChanged: { cpuHist = []; lastSample = null; flick.contentY = 0 }
  // Something to draw from the first moment: the reading already on screen.
  onItemChanged: if (item && !cpuHist.length) cpuHist = [item.cpu]
  onSChanged: {
    if (!s || s === lastSample) return
    lastSample = s
    // A reading without processes -- a network page tick -- says nothing.
    if (!item || !s.processes.length) return
    cpuHist = app.pushSample(cpuHist, item.cpu)
  }

  function openProcess(pid) {
    var sel = { kind: "process", pid: pid }
    if (root.paged) root.app.openDetail(sel)
    else root.app.selection = sel
  }
  function openApp(key) {
    var sel = { kind: "app", key: key }
    if (root.paged) root.app.openDetail(sel)
    else root.app.selection = sel
  }

  function startedText(p) {
    if (!s || p.started === undefined) return ""
    var ago = Math.max(0, s.uptime - p.started)
    return Sysinfo.humanSeconds(ago) + " ago"
  }

  // ------------------------------------------------------------ header

  Item {
    id: header
    width: parent.width
    height: root.app.compact ? 60 : 64

    IconButton {
      id: backButton
      visible: root.paged
      x: 4
      anchors.verticalCenter: parent.verticalCenter
      width: visible ? implicitWidth : 0
      app: root.app
      glyph: G.back
      label: "Back"
      onClicked: root.app.back()
    }
    Column {
      anchors.left: backButton.visible ? backButton.right : parent.left
      anchors.leftMargin: backButton.visible ? 4 : 20
      anchors.right: closeButton.visible ? closeButton.left : parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      Text {
        width: parent.width
        text: root.item ? root.item.name : (root.isApp ? "App" : "Process")
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.paged ? 21 : 19
        font.weight: Font.Bold
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: !root.item ? "" : root.isApp
          ? (root.item.kernel ? root.item.pids.length + " kernel threads" : root.item.pids.length === 1 ? "One process" : root.item.pids.length + " processes")
          : "pid " + root.item.pid + " · " + root.item.state
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        elide: Text.ElideRight
      }
    }
    IconButton {
      id: closeButton
      visible: !root.paged
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      glyph: G.close
      label: "Close"
      onClicked: root.app.selection = null
    }
  }

  // It went away while you were looking.
  Column {
    anchors.centerIn: parent
    visible: root.sel !== null && root.s !== null && root.item === null && root.s.processes.length > 0
    spacing: 12
    width: parent.width - 48
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: root.isApp ? "Nothing by that name is running any more" : "This process has exited"
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
    }
    Button {
      anchors.horizontalCenter: parent.horizontalCenter
      app: root.app
      text: root.paged ? "Back" : "Close"
      onClicked: root.paged ? root.app.back() : (root.app.selection = null)
    }
  }

  // ------------------------------------------------------------ body

  Flickable {
    id: flick
    anchors.top: header.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    visible: root.item !== null
    contentWidth: width
    contentHeight: body.implicitHeight + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      x: root.paged ? root.app.ui.gutter : 16
      y: 4
      width: Math.min(flick.width - x * 2, 720)
      spacing: 14

      // What it costs, big.
      Row {
        width: parent.width
        spacing: 10
        Stat {
          app: root.app
          width: (parent.width - 10) / 2
          label: "Processor"
          glyph: G.processor
          value: root.item ? Sysinfo.taskPercent(root.item.cpu) : ""
          valueColor: root.item ? root.app.loadColor(root.item.cpu) : root.app.ui.text
          note: "of the whole machine"
        }
        Stat {
          app: root.app
          width: (parent.width - 10) / 2
          label: "Memory"
          glyph: G.memory
          value: root.item ? Sysinfo.humanBytes(root.item.rss) : ""
          note: root.item && root.s && root.s.memory.total ? Sysinfo.humanPercent(root.item.rss / root.s.memory.total) + " of it" : ""
        }
      }

      Bars {
        app: root.app
        width: parent.width
        implicitHeight: 56
        values: root.cpuHist.map(function (v) { return Math.min(1, v * 4) })
        slots: 40
        load: true
      }
      Text {
        width: parent.width
        text: "Processor since you opened this, against a quarter of the machine"
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        wrapMode: Text.Wrap
      }

      // A process's particulars.
      Column {
        visible: !root.isApp
        width: parent.width
        spacing: 0
        Repeater {
          model: {
            var p = root.item
            if (!p || root.isApp) return []
            var owner = root.s && root.s.ownerPid === p.pid ? root.s.owner : ""
            var rows = [
              { label: "State", value: p.state },
              { label: "Threads", value: String(p.threads) },
              { label: "Processor time", value: Sysinfo.humanSeconds(p.seconds) },
              { label: "Started", value: root.startedText(p) },
              { label: "User", value: owner || "…" },
              { label: "Parent", value: root.parentProc ? root.parentProc.name + " · " + p.ppid : "pid " + p.ppid, pid: root.parentProc ? p.ppid : 0 },
              { label: "Part of", value: root.app.findApp(root.app.appKeyOf(p)) ? root.app.findApp(root.app.appKeyOf(p)).name : "", key: root.app.appKeyOf(p) }
            ]
            return rows
          }
          delegate: Rectangle {
            id: fact
            required property var modelData
            readonly property bool link: (modelData.pid || 0) > 0 || (modelData.key || "") !== ""
            width: parent.width
            height: 44
            color: factMouse.pressed ? root.app.ui.pressed : factMouse.containsMouse && link ? root.app.ui.hover : "transparent"
            radius: root.app.ui.radius
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.app.ui.divider }
            Text {
              x: 4
              anchors.verticalCenter: parent.verticalCenter
              text: fact.modelData.label
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
            Row {
              anchors.right: parent.right
              anchors.rightMargin: 4
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, fact.width * 0.6)
                horizontalAlignment: Text.AlignRight
                text: fact.modelData.value
                color: fact.link ? root.app.ui.accent : root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
                font.features: ({ "tnum": 1 })
                elide: Text.ElideRight
              }
              Icon {
                visible: fact.link
                anchors.verticalCenter: parent.verticalCenter
                app: root.app
                text: G.chevronRight
                size: 15
                width: 18
                color: root.app.ui.accent
              }
            }
            MouseArea {
              id: factMouse
              anchors.fill: parent
              enabled: fact.link
              hoverEnabled: !root.app.compact
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (fact.modelData.pid) root.openProcess(fact.modelData.pid)
                else if (fact.modelData.key) root.openApp(fact.modelData.key)
              }
            }
          }
        }
      }

      // The command line, which can be selected and copied.
      Rectangle {
        visible: !root.isApp && root.item !== null
        width: parent.width
        height: cmd.implicitHeight + 20
        radius: root.app.ui.radius
        color: root.app.ui.well
        TextEdit {
          id: cmd
          x: 10
          y: 10
          width: parent.width - 20
          readOnly: true
          selectByMouse: !root.app.compact
          wrapMode: TextEdit.WrapAnywhere
          text: root.item && !root.isApp ? (root.item.cmdline || "[" + root.item.name + "] — a kernel thread, with no command line") : ""
          color: root.item && root.item.cmdline ? root.app.ui.text : root.app.ui.muted
          selectionColor: root.app.ui.accent
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: root.app.ui.fs.xs
        }
      }

      // An app's processes, lowest pid first: the one that started the rest.
      Column {
        visible: root.isApp && root.procs.length > 0
        width: parent.width
        spacing: 0
        Text {
          text: "Processes"
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: Font.DemiBold
          bottomPadding: 6
        }
        Repeater {
          model: root.isApp ? root.procs.slice().sort(function (a, b) { return a.pid - b.pid }).slice(0, 40) : []
          delegate: TaskRow {
            required property var modelData
            app: root.app
            width: parent.width
            implicitHeight: 50
            item: modelData
            figure: "cpu"
            onClicked: root.openProcess(modelData.pid)
          }
        }
        Text {
          visible: root.procs.length > 40
          text: "and " + (root.procs.length - 40) + " more"
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          topPadding: 6
        }
      }

      // The two signals.
      Column {
        visible: root.item !== null && !root.item.kernel
        width: parent.width
        spacing: 8
        Item { width: 1; height: 2 }
        Row {
          spacing: 10
          Button {
            app: root.app
            glyph: G.stop
            text: root.isApp && root.item && root.item.pids.length > 1 ? "End app" : "End task"
            onClicked: root.app.askEnd(root.sel, false)
          }
          Button {
            app: root.app
            glyph: G.kill
            text: "Force stop"
            tint: root.app.ui.bad
            active: true
            onClicked: root.app.askEnd(root.sel, true)
          }
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: "End task asks it to stop, and it can save first. Force stop takes it away mid-write."
            + (root.app.compact ? "" : " Delete and Shift+Delete do the same.")
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
        }
      }
    }
  }
}
