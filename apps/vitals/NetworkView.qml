import QtQuick
import "kit"
import "Sysinfo.js" as Sysinfo
import "Glyphs.js" as G

// One card per interface: what it is moving now, the last two minutes of it
// mirrored -- down above the line, up below -- and what it has moved since
// the machine started.
Item {
  id: root
  property var app

  readonly property var s: app.sample
  readonly property var ifaces: s ? s.interfaces : []

  Flickable {
    id: flick
    anchors.fill: parent
    visible: root.s !== null
    contentWidth: width
    contentHeight: grid.height + root.app.ui.gutter * 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Grid {
      id: grid
      x: root.app.ui.gutter
      y: root.app.compact ? 4 : 8
      width: flick.width - root.app.ui.gutter * 2
      columns: Math.min(root.app.columns, 2)
      columnSpacing: root.app.ui.gutter
      rowSpacing: root.app.ui.gutter

      Repeater {
        model: root.ifaces
        delegate: Card {
          id: card
          required property var modelData
          readonly property var iface: modelData
          readonly property var hist: root.app.netHistory[iface.name] || ({ rx: [], tx: [] })
          readonly property real range: root.app.netScale(iface.name)
          app: root.app
          width: (grid.width - (grid.columns - 1) * grid.columnSpacing) / grid.columns
          title: iface.name
          glyph: iface.name === "lo" ? G.loopback : iface.wireless ? G.wifi : G.ethernet
          glyphColor: iface.up ? root.app.ui.good : root.app.ui.muted
          trailing: iface.name === "lo" ? "loopback" : iface.state
          trailingColor: iface.up ? root.app.ui.good : root.app.ui.muted

          // A down interface has no rates and never will; two boxes of
          // "0 B/s" under it would be a claim that something is measured.
          Row {
            visible: card.iface.up || card.iface.name === "lo"
            width: parent.width
            spacing: 12
            Rate { app: root.app; width: (parent.width - 12) / 2; glyph: G.down; color: root.app.ui.down; label: "Down"; value: Sysinfo.humanRate(card.iface.rx_rate); note: Sysinfo.humanBytes(card.iface.rx) + " total" }
            Rate { app: root.app; width: (parent.width - 12) / 2; glyph: G.up; color: root.app.ui.up; label: "Up"; value: Sysinfo.humanRate(card.iface.tx_rate); note: Sysinfo.humanBytes(card.iface.tx) + " total" }
          }

          MirrorBars {
            visible: card.iface.up || card.iface.name === "lo"
            app: root.app
            width: parent.width
            implicitHeight: root.app.compact ? 96 : 120
            down: card.hist.rx
            up: card.hist.tx
            slots: root.app.historyLength
            range: card.range
          }
          Text {
            visible: card.iface.up || card.iface.name === "lo"
            text: "Scale " + Sysinfo.humanRate(card.range) + " each way"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }

          // Signal in dBm where the driver reports it, because a percentage
          // whose denominator is a guess is worse than a number that means
          // something.
          Labelled {
            visible: card.iface.wireless && (card.iface.quality !== null || card.iface.signal !== null)
            app: root.app
            width: parent.width
            glyph: G.wifi
            label: "Signal"
            value: card.iface.signal !== null ? card.iface.signal + " dBm · " + Sysinfo.humanPercent(card.iface.quality || 0)
              : (card.iface.quality !== null ? Sysinfo.humanPercent(card.iface.quality) : "")
            fraction: card.iface.quality || 0
            color: (card.iface.quality || 0) < 0.3 ? root.app.ui.bad : root.app.ui.good
          }

          Text {
            visible: !card.iface.up && card.iface.name !== "lo"
            width: parent.width
            wrapMode: Text.Wrap
            text: "Not connected. " + Sysinfo.humanBytes(card.iface.rx) + " down and " + Sysinfo.humanBytes(card.iface.tx) + " up since the machine started."
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
        }
      }
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.s !== null && root.ifaces.length === 0
    text: "No network interfaces"
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.md
  }
}
