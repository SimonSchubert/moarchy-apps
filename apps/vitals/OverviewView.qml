import QtQuick
import "kit"
import "Sysinfo.js" as Sysinfo
import "Glyphs.js" as G

// Everything at once: btop's boxes, as cards. One column on a phone, two or
// three across on a desktop, and every card a way into the page behind it.
Item {
  id: root
  property var app

  readonly property var s: app.sample

  // Which card goes in which column, so the columns come out about the same
  // height at each width rather than one tall and one short.
  readonly property var layout: app.columns >= 3
    ? [["cpu", "busy"], ["memory", "storage"], ["network", "power"]]
    : app.columns === 2
      ? [["cpu", "network", "power"], ["memory", "busy", "storage"]]
      : [["cpu", "memory", "busy", "network", "storage", "power"]]

  readonly property var cards: ({
    cpu: cpuCard, memory: memoryCard, busy: busyCard,
    network: networkCard, storage: storageCard, power: powerCard
  })

  Page {
    anchors.fill: parent
    visible: root.s !== null
    app: root.app
    layout: root.layout
    cards: root.cards
  }

  // ------------------------------------------------------------ cards

  Component {
    id: cpuCard
    Card {
      app: root.app
      title: "Processor"
      glyph: G.processor
      glyphColor: root.app.ui.cpu
      trailing: root.s ? root.s.cpu.cores.length + " cores" + (root.s.cpu.frequency !== null ? " · " + (root.s.cpu.frequency / 1000).toFixed(2) + " GHz" : "") : ""
      clickable: true
      onClicked: root.app.setTab("processor")

      Figure {
        app: root.app
        width: parent.width
        value: root.s ? Sysinfo.humanPercent(root.s.cpu.total) : ""
        valueColor: root.s ? root.app.loadColor(root.s.cpu.total) : root.app.ui.muted
        caption: root.s ? "load " + root.s.cpu.load.map(function (v) { return v.toFixed(2) }).join("  ") : ""
        side: root.s && root.s.cpu.temperature !== null ? Math.round(root.s.cpu.temperature) + "°C" : ""
        sideColor: root.s ? root.app.heatColor(root.s.cpu.temperature) : root.app.ui.muted
        sideGlyph: G.heat
      }
      Bars {
        app: root.app
        width: parent.width
        implicitHeight: root.app.compact ? 56 : 72
        values: root.app.cpuHistory
        slots: root.app.historyLength
        color: root.app.ui.cpu
      }
      CoreBars {
        app: root.app
        width: parent.width
        cores: root.s ? root.s.cpu.cores : []
      }
    }
  }

  Component {
    id: memoryCard
    Card {
      app: root.app
      title: "Memory"
      glyph: G.memory
      glyphColor: root.app.ui.mem
      trailing: root.s ? Sysinfo.humanBytes(root.s.memory.total) : ""
      clickable: true
      onClicked: root.app.setTab("memory")

      Figure {
        app: root.app
        width: parent.width
        value: root.s ? Sysinfo.humanBytes(root.s.memory.used) : ""
        caption: root.s ? Sysinfo.humanBytes(root.s.memory.available) + " available · " + Sysinfo.humanBytes(root.s.memory.cached) + " cache" : ""
        side: root.s ? Sysinfo.humanPercent(root.s.memory.fraction) : ""
        sideColor: root.s ? root.app.loadColor(root.s.memory.fraction) : root.app.ui.muted
      }
      Meter {
        app: root.app
        width: parent.width
        implicitHeight: 12
        value: root.s ? root.s.memory.fraction : 0
        extra: root.s && root.s.memory.total ? Math.min(1 - root.s.memory.fraction, root.s.memory.cached / root.s.memory.total) : 0
        fill: root.app.ui.mem
      }
      Bars {
        app: root.app
        width: parent.width
        implicitHeight: root.app.compact ? 44 : 56
        values: root.app.memHistory
        slots: root.app.historyLength
        color: root.app.ui.mem
      }
      Labelled {
        app: root.app
        width: parent.width
        visible: root.s !== null && root.s.memory.swap_total > 0
        label: "Swap"
        value: root.s ? Sysinfo.humanBytes(root.s.memory.swap_used) + " of " + Sysinfo.humanBytes(root.s.memory.swap_total) : ""
        fraction: root.s ? root.s.memory.swap_fraction : 0
        color: root.app.ui.swap
      }
    }
  }

  Component {
    id: busyCard
    Card {
      app: root.app
      title: "Busiest apps"
      glyph: G.tasks
      trailing: root.s ? root.s.processes.length + " processes" : ""
      clickable: true
      onClicked: root.app.setTab("tasks")
      pad: root.app.compact ? 10 : 14

      Repeater {
        model: root.app.busiest(5)
        delegate: TaskRow {
          required property var modelData
          app: root.app
          width: parent.width
          implicitHeight: 50
          item: modelData
          figure: "cpu"
          onClicked: root.app.openDetail({ kind: "app", key: modelData.key })
        }
      }
    }
  }

  Component {
    id: networkCard
    Card {
      id: net
      readonly property var iface: root.app.mainInterface
      app: root.app
      title: "Network"
      glyph: iface && iface.wireless ? G.wifi : G.ethernet
      glyphColor: iface && iface.up ? root.app.ui.good : root.app.ui.muted
      trailing: iface ? iface.name : ""
      clickable: true
      onClicked: root.app.setTab("network")

      Row {
        width: parent.width
        spacing: 12
        Rate { app: root.app; width: (parent.width - 12) / 2; glyph: G.down; color: root.app.ui.down; label: "Down"; value: net.iface ? Sysinfo.humanRate(net.iface.rx_rate) : "—" }
        Rate { app: root.app; width: (parent.width - 12) / 2; glyph: G.up; color: root.app.ui.up; label: "Up"; value: net.iface ? Sysinfo.humanRate(net.iface.tx_rate) : "—" }
      }
      MirrorBars {
        app: root.app
        width: parent.width
        implicitHeight: root.app.compact ? 64 : 80
        down: net.iface && root.app.netHistory[net.iface.name] ? root.app.netHistory[net.iface.name].rx : []
        up: net.iface && root.app.netHistory[net.iface.name] ? root.app.netHistory[net.iface.name].tx : []
        slots: root.app.historyLength
        range: net.iface ? root.app.netScale(net.iface.name) : 1024
      }
    }
  }

  Component {
    id: storageCard
    Card {
      app: root.app
      title: "Storage"
      glyph: G.disk
      glyphColor: root.app.ui.disk
      trailing: root.s ? "↓ " + Sysinfo.humanRate(root.s.io.read_rate) + "  ↑ " + Sysinfo.humanRate(root.s.io.write_rate) : ""
      visible: root.s !== null

      Repeater {
        model: root.s ? root.s.storage.slice(0, 4) : []
        delegate: Labelled {
          required property var modelData
          app: root.app
          width: parent.width
          glyph: modelData.mount.indexOf("/run/media") === 0 || modelData.mount.indexOf("/media") === 0 ? G.sd : G.disk
          label: modelData.mount
          value: Sysinfo.humanBytes(modelData.used) + " of " + Sysinfo.humanBytes(modelData.total)
          fraction: modelData.fraction
          color: modelData.fraction >= 0.9 ? root.app.ui.bad : root.app.ui.disk
        }
      }
      Text {
        visible: root.s !== null && root.s.storage.length === 0
        text: "No local filesystems reported"
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
    }
  }

  Component {
    id: powerCard
    Card {
      id: power
      readonly property var bat: root.s ? root.s.battery : null
      app: root.app
      title: bat ? "Battery" : "System"
      glyph: bat ? (bat.status === "Charging" ? G.charging : G.battery) : G.info

      Grid {
        width: parent.width
        columns: 2
        columnSpacing: 8
        rowSpacing: 8
        Repeater {
          model: {
            if (!root.s) return []
            var rows = []
            var b = power.bat
            if (b) {
              rows.push({ label: "Charge", value: b.percent + "%", note: b.status, glyph: G.battery,
                          color: b.percent <= 15 && b.status !== "Charging" ? root.app.ui.bad : root.app.ui.text })
              if (b.watts !== null) rows.push({ label: b.status === "Charging" ? "Charging at" : "Drawing", value: b.watts.toFixed(1) + " W", glyph: G.flash })
            }
            if (root.s.cpu.temperature !== null)
              rows.push({ label: "Heat", value: Math.round(root.s.cpu.temperature) + "°C", glyph: G.heat, color: root.app.heatColor(root.s.cpu.temperature) })
            rows.push({ label: "Tasks", value: root.s.cpu.running + " of " + root.s.cpu.tasks, note: "running", glyph: G.pulse })
            rows.push({ label: "Up", value: Sysinfo.humanSeconds(root.s.uptime), glyph: G.clock })
            if (root.s.machine.kernel) rows.push({ label: "Kernel", value: root.s.machine.kernel.split("-")[0], note: root.s.machine.kernel, glyph: G.kernel })
            return rows
          }
          delegate: Stat {
            required property var modelData
            app: root.app
            width: (parent.width - 8) / 2
            label: modelData.label
            value: modelData.value
            note: modelData.note || ""
            glyph: modelData.glyph || ""
            valueColor: modelData.color || root.app.ui.text
          }
        }
      }
    }
  }
}
