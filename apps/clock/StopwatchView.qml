import QtQuick
import "kit"
import "Watch.js" as Watch

// The stopwatch: a ring that goes round once a minute, the time inside it,
// Lap-or-Reset and Start-or-Stop, and the laps -- under it on a phone,
// beside it on a desktop.
Item {
  id: root
  property var app

  readonly property bool wide: !app.compact
  readonly property bool hasLaps: app.watch.laps.length > 0

  Item {
    id: stage
    anchors.left: parent.left
    anchors.top: parent.top
    width: root.wide && root.hasLaps ? parent.width - laps.width - 24 : parent.width
    height: root.wide || !root.hasLaps ? parent.height : block.implicitHeight + 24

    Column {
      id: block
      anchors.centerIn: parent
      spacing: 16

      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property int side: root.wide ? Math.min(320, stage.height - 140, stage.width - 48) : 210
        width: side
        height: side

        Ring {
          anchors.fill: parent
          thickness: root.wide ? 9 : 7
          // The minute, not the hour: a ring that has to show an hour moves a
          // degree a minute and reads as broken.
          progress: Watch.watchSweep(root.app.elapsed)
          ink: root.app.watch.running ? root.app.ui.accent : root.app.ui.muted
          track: root.app.ui.text
        }

        Column {
          anchors.centerIn: parent
          Digits {
            anchors.horizontalCenter: parent.horizontalCenter
            family: root.app.ui.font
            text: Watch.watchText(root.app.elapsed).slice(0, -2)
            tail: Watch.watchText(root.app.elapsed).slice(-2)
            pixelSize: Math.round(root.app.body * (root.wide ? 3.3 : 2.7))
            weight: Font.Light
            color: root.app.ui.text
            tailColor: root.app.watch.running ? root.app.ui.accent : root.app.ui.muted
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.app.watch.laps.length
              ? "LAP " + (root.app.watch.laps.length + (root.app.watch.running ? 1 : 0))
              : (root.app.watch.running ? "RUNNING" : (root.app.elapsed > 0 ? "STOPPED" : "READY"))
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
            font.weight: Font.Bold
            font.letterSpacing: root.app.ui.tracking
          }
        }
      }

      // Lap while it runs, Reset once it has stopped: one key, because the two
      // are never wanted at the same moment.
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12
        Button {
          app: root.app
          text: root.app.watch.running ? "Lap" : "Reset"
          enabled: root.app.watch.running || root.app.elapsed > 0
          onClicked: root.app.watch.running ? root.app.watchLap() : root.app.watchReset()
        }
        Button {
          app: root.app
          primary: true
          tint: root.app.watch.running ? root.app.ui.bad : root.app.ui.accent
          text: root.app.watch.running ? "Stop" : (root.app.elapsed > 0 ? "Resume" : "Start")
          onClicked: root.app.watch.running ? root.app.watchStop() : root.app.watchStart()
        }
      }
    }
  }

  Rectangle {
    id: laps
    visible: root.hasLaps
    x: root.wide ? parent.width - width - 24 : root.app.ui.gutter
    y: root.wide ? 12 : stage.height
    width: root.wide ? Math.min(380, parent.width * 0.45) : parent.width - root.app.ui.gutter * 2
    height: root.wide ? parent.height - 24 : parent.height - stage.height - root.app.ui.gutter
    radius: root.app.ui.radius
    color: root.app.ui.surface
    border.width: 1
    border.color: root.app.ui.line

    ListView {
      id: list
      anchors.fill: parent
      anchors.margins: 6
      clip: true
      model: root.app.laps
      boundsBehavior: Flickable.StopAtBounds
      // The newest lap at the top, where the eye already is.
      delegate: Item {
        id: lap
        required property var modelData
        width: list.width
        height: 38
        // Best and worst in the theme's green and red, and in bold as well,
        // because a colour on its own is not a signal everybody gets.
        readonly property color mark: modelData.best ? root.app.ui.good
          : modelData.worst ? root.app.ui.bad : root.app.ui.text
        Row {
          anchors.fill: parent
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            text: "#" + lap.modelData.index
            color: lap.modelData.running ? root.app.ui.accent : root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
          Digits {
            anchors.verticalCenter: parent.verticalCenter
            width: 110
            family: root.app.ui.font
            text: Watch.watchText(lap.modelData.lap).slice(0, -2)
            tail: Watch.watchText(lap.modelData.lap).slice(-2)
            pixelSize: root.app.body
            weight: lap.modelData.best || lap.modelData.worst ? Font.Bold : Font.Normal
            color: lap.mark
            tailColor: root.app.ui.alpha(lap.mark, 0.7)
          }
          Item { width: 8; height: 1 }
          Digits {
            anchors.verticalCenter: parent.verticalCenter
            family: root.app.ui.font
            text: Watch.watchText(lap.modelData.at).slice(0, -2)
            tail: Watch.watchText(lap.modelData.at).slice(-2)
            pixelSize: root.app.body
            color: root.app.ui.muted
            tailColor: root.app.ui.alpha(root.app.ui.muted, 0.7)
          }
        }
      }
    }
  }
}
