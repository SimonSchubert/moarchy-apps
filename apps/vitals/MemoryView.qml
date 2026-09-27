import QtQuick
import "Sysinfo.js" as Sysinfo
import "Glyphs.js" as G

// Memory: how much is taken, how much would be given back, swap, and who has
// the most of it. Storage is here too -- the other place a phone runs out of
// room.
Item {
  id: root
  property var app

  readonly property var s: app.sample

  readonly property var layout: app.columns >= 2
    ? [["now", "facts", "storage"], ["largest"]]
    : [["now", "largest", "facts", "storage"]]

  readonly property var cards: ({ now: nowCard, facts: factsCard, storage: storageCard, largest: largestCard })

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
      title: "In use"
      glyph: G.memory
      glyphColor: root.app.ui.mem
      trailing: root.s ? "of " + Sysinfo.humanBytes(root.s.memory.total) : ""

      Figure {
        app: root.app
        width: parent.width
        value: root.s ? Sysinfo.humanBytes(root.s.memory.used) : ""
        caption: "what a new app could not have without swapping"
        side: root.s ? Sysinfo.humanPercent(root.s.memory.fraction) : ""
        sideColor: root.s ? root.app.loadColor(root.s.memory.fraction) : root.app.ui.muted
      }
      Meter {
        app: root.app
        width: parent.width
        implicitHeight: 14
        value: root.s ? root.s.memory.fraction : 0
        extra: root.s && root.s.memory.total ? Math.min(1 - root.s.memory.fraction, root.s.memory.cached / root.s.memory.total) : 0
        fill: root.app.ui.mem
      }
      Row {
        spacing: 16
        Repeater {
          model: [
            { label: "Used", color: root.app.ui.mem },
            { label: "Cache, given back when needed", color: root.app.alpha(root.app.ui.mem, 0.35) }
          ]
          delegate: Row {
            required property var modelData
            spacing: 6
            Rectangle { width: 10; height: 10; radius: 5; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }
            Text {
              text: modelData.label
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xs
            }
          }
        }
      }
      Bars {
        app: root.app
        width: parent.width
        implicitHeight: root.app.compact ? 80 : 120
        values: root.app.memHistory
        slots: root.app.historyLength
        color: root.app.ui.mem
      }
      Labelled {
        app: root.app
        width: parent.width
        visible: root.s !== null && root.s.memory.swap_total > 0
        glyph: G.memory
        label: "Swap"
        value: root.s ? Sysinfo.humanBytes(root.s.memory.swap_used) + " of " + Sysinfo.humanBytes(root.s.memory.swap_total) : ""
        fraction: root.s ? root.s.memory.swap_fraction : 0
        color: root.app.ui.swap
      }
    }
  }

  Component {
    id: factsCard
    Grid {
      columns: 2
      columnSpacing: 10
      rowSpacing: 10
      Repeater {
        model: {
          if (!root.s) return []
          var m = root.s.memory
          var rows = [
            { label: "Available", value: Sysinfo.humanBytes(m.available), glyph: G.check },
            { label: "Cache", value: Sysinfo.humanBytes(m.cached), glyph: G.memory }
          ]
          if (m.swap_total > 0)
            rows.push({ label: "Swap", value: Sysinfo.humanBytes(m.swap_used), note: "of " + Sysinfo.humanBytes(m.swap_total), glyph: G.memory })
          rows.push({ label: "Disk read", value: Sysinfo.humanRate(root.s.io.read_rate), glyph: G.down })
          rows.push({ label: "Disk write", value: Sysinfo.humanRate(root.s.io.write_rate), glyph: G.up })
          return rows
        }
        delegate: Stat {
          required property var modelData
          app: root.app
          width: (parent.width - 10) / 2
          label: modelData.label
          value: modelData.value
          note: modelData.note || ""
          glyph: modelData.glyph || ""
        }
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
      Repeater {
        model: root.s ? root.s.storage : []
        delegate: Labelled {
          required property var modelData
          app: root.app
          width: parent.width
          glyph: modelData.mount.indexOf("/run/media") === 0 || modelData.mount.indexOf("/media") === 0 ? G.sd : G.disk
          label: modelData.mount
          value: Sysinfo.humanBytes(modelData.free) + " free of " + Sysinfo.humanBytes(modelData.total)
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
    id: largestCard
    Card {
      app: root.app
      title: "Most memory"
      glyph: G.tasks
      trailing: "resident size"
      pad: root.app.compact ? 10 : 14
      Repeater {
        model: root.app.largest(root.app.compact ? 6 : 10)
        delegate: TaskRow {
          required property var modelData
          app: root.app
          width: parent.width
          item: modelData
          figure: "memory"
          onClicked: root.app.openDetail({ kind: "app", key: modelData.key })
        }
      }
      Button {
        app: root.app
        text: "All tasks"
        glyph: G.chevronRight
        onClicked: { root.app.store.set("taskSort", "memory"); root.app.setTab("tasks") }
      }
    }
  }
}
