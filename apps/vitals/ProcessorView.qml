import QtQuick
import "kit"
import "Sysinfo.js" as Sysinfo
import "Glyphs.js" as G

// The processor: how busy, for how long, on which core, and because of what.
Item {
  id: root
  property var app

  readonly property var s: app.sample

  readonly property var layout: app.columns >= 2
    ? [["now", "cores", "facts"], ["busy"]]
    : [["now", "busy", "cores", "facts"]]

  readonly property var cards: ({ now: nowCard, cores: coresCard, facts: factsCard, busy: busyCard })

  Page {
    anchors.fill: parent
    visible: root.s !== null
    app: root.app
    layout: root.layout
    cards: root.cards
  }

  Component {
    id: nowCard
    Card {
      app: root.app
      title: "Across every core"
      glyph: G.processor
      glyphColor: root.app.ui.cpu
      trailing: (root.app.historyLength * root.app.interval / 60000) + " min"

      Figure {
        app: root.app
        width: parent.width
        value: root.s ? Sysinfo.humanPercent(root.s.cpu.total) : ""
        valueColor: root.s ? root.app.loadColor(root.s.cpu.total) : root.app.ui.muted
        caption: root.s ? root.s.cpu.running + " running of " + root.s.cpu.tasks + " tasks" : ""
        side: root.s && root.s.cpu.frequency !== null ? (root.s.cpu.frequency / 1000).toFixed(2) + " GHz" : ""
        sideGlyph: G.gauge
      }
      Bars {
        app: root.app
        width: parent.width
        implicitHeight: root.app.compact ? 100 : 150
        values: root.app.cpuHistory
        slots: root.app.historyLength
        load: true
      }
    }
  }

  Component {
    id: coresCard
    Card {
      app: root.app
      title: "Cores"
      trailing: root.s ? String(root.s.cpu.cores.length) : ""
      CoreBars {
        app: root.app
        width: parent.width
        detailed: true
        perRow: root.app.compact || (root.s && root.s.cpu.cores.length <= 4) ? 1 : 2
        cores: root.s ? root.s.cpu.cores : []
      }
    }
  }

  Component {
    id: factsCard
    Grid {
      id: facts
      columns: root.app.compact ? 2 : 3
      columnSpacing: 10
      rowSpacing: 10
      Repeater {
        model: {
          if (!root.s) return []
          var c = root.s.cpu
          var rows = [
            { label: "Load", value: c.load[0].toFixed(2), note: c.load[1].toFixed(2) + " · " + c.load[2].toFixed(2) + " over 5 · 15 min", glyph: G.pulse },
            { label: "Tasks", value: String(c.tasks), note: c.running + " running", glyph: G.tasks }
          ]
          if (c.temperature !== null)
            rows.push({ label: "Heat", value: Math.round(c.temperature) + "°C", glyph: G.heat, color: root.app.heatColor(c.temperature) })
          if (c.frequency !== null)
            rows.push({ label: "Clock", value: Math.round(c.frequency) + " MHz", note: "average of the cores", glyph: G.gauge })
          rows.push({ label: "Up", value: Sysinfo.humanSeconds(root.s.uptime), glyph: G.clock })
          return rows
        }
        delegate: Stat {
          required property var modelData
          app: root.app
          width: (facts.width - (facts.columns - 1) * 10) / facts.columns
          label: modelData.label
          value: modelData.value
          note: modelData.note || ""
          glyph: modelData.glyph || ""
          valueColor: modelData.color || root.app.ui.text
        }
      }
    }
  }

  Component {
    id: busyCard
    Card {
      app: root.app
      title: "Busiest apps"
      glyph: G.tasks
      trailing: "share of the whole machine"
      pad: root.app.compact ? 10 : 14
      Repeater {
        model: root.app.busiest(root.app.compact ? 6 : 10)
        delegate: TaskRow {
          required property var modelData
          app: root.app
          width: parent.width
          item: modelData
          figure: "cpu"
          onClicked: root.app.openDetail({ kind: "app", key: modelData.key })
        }
      }
      Button {
        app: root.app
        text: "All tasks"
        glyph: G.chevronRight
        onClicked: root.app.setTab("tasks")
      }
    }
  }
}
