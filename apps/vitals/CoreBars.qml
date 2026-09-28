import QtQuick
import "Sysinfo.js" as Sysinfo

// One bar per core, which is the reading that matters on a big.LITTLE phone:
// one pegged core of four is 25% on the headline figure and feels like the
// phone has stopped.
//
// Short vertical bars side by side when there are many, so sixteen cores fit
// a card's width; with `detailed`, a labelled row per core instead.
Item {
  id: root
  property var app
  property var cores: []
  property bool detailed: false
  property int perRow: app.compact ? 1 : 2

  implicitHeight: detailed ? list.implicitHeight : 36

  Row {
    id: strip
    visible: !root.detailed
    anchors.fill: parent
    spacing: root.cores.length > 12 ? 2 : 4
    Repeater {
      model: root.detailed ? [] : root.cores
      delegate: Rectangle {
        required property var modelData
        width: (root.width - (root.cores.length - 1) * strip.spacing) / Math.max(1, root.cores.length)
        height: root.height
        radius: Math.min(root.app.ui.radius, width / 2)
        color: root.app.ui.well
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: Math.max(3, parent.height * modelData)
          radius: parent.radius
          color: root.app.loadColor(modelData)
        }
      }
    }
  }

  Grid {
    id: list
    visible: root.detailed
    width: parent.width
    columns: root.perRow
    columnSpacing: 20
    rowSpacing: 8
    Repeater {
      model: root.detailed ? root.cores : []
      delegate: Row {
        required property var modelData
        required property int index
        width: (list.width - (root.perRow - 1) * list.columnSpacing) / root.perRow
        height: 18
        spacing: 8
        Text {
          width: 30
          anchors.verticalCenter: parent.verticalCenter
          text: "c" + index
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          font.features: ({ "tnum": 1 })
        }
        Meter {
          app: root.app
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 30 - 44 - 16
          implicitHeight: 10
          value: modelData
          fill: root.app.loadColor(modelData)
        }
        Text {
          width: 44
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: Sysinfo.humanPercent(modelData)
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          font.features: ({ "tnum": 1 })
        }
      }
    }
  }
}
