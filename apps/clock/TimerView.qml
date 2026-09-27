import QtQuick
import "kit"
import "Watch.js" as Watch

// The timer: a keypad to type one in, and once it runs, a ring emptying
// anticlockwise with what is left inside it. On a desktop the keypad's
// number sits beside the keys and the physical keyboard types too.
Item {
  id: root
  property var app

  readonly property bool wide: !app.compact
  readonly property bool running: app.timer.total > 0

  // A twelve-key pad. "00" is two taps in one, because a duration is almost
  // always a round number of minutes.
  readonly property var keypad: [
    { text: "1", key: 1 }, { text: "2", key: 2 }, { text: "3", key: 3 },
    { text: "4", key: 4 }, { text: "5", key: 5 }, { text: "6", key: 6 },
    { text: "7", key: 7 }, { text: "8", key: 8 }, { text: "9", key: 9 },
    { text: "00", key: -2 }, { text: "0", key: 0 }, { text: "⌫", key: -1 }
  ]

  // ------------------------------------------------------------ running

  Column {
    anchors.centerIn: parent
    visible: root.running
    spacing: 24

    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      readonly property int side: root.wide ? Math.min(340, root.height - 150) : 232
      width: side
      height: side

      Ring {
        anchors.fill: parent
        thickness: root.wide ? 10 : 8
        progress: Watch.timerProgress(root.app.timer, root.app.now)
        // Anticlockwise, so the arc that is left is the arc that is left.
        reverse: true
        ink: root.app.timer.running ? root.app.ui.accent : root.app.ui.muted
        track: root.app.ui.text
      }
      Column {
        anchors.centerIn: parent
        spacing: 2
        Digits {
          anchors.horizontalCenter: parent.horizontalCenter
          family: root.app.ui.font
          text: Watch.timerText(root.app.remaining)
          pixelSize: Math.round(root.app.body * (root.wide ? 3.6 : 2.9))
          weight: Font.Light
          color: root.app.ui.text
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: (root.app.timer.running ? "of " : "paused, of ") + Watch.spanLabel(root.app.timer.total)
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 10
      Button { app: root.app; text: "+1 min"; onClicked: root.app.timerAdd() }
      Button {
        app: root.app
        primary: true
        text: root.app.timer.running ? "Pause" : "Resume"
        onClicked: root.app.timer.running ? root.app.timerPause() : root.app.timerResume()
      }
      Button { app: root.app; text: "Cancel"; tint: root.app.ui.bad; active: true; onClicked: root.app.timerCancel() }
    }
  }

  // ------------------------------------------------------------ setting one

  Grid {
    anchors.centerIn: parent
    visible: !root.running
    columns: root.wide ? 2 : 1
    columnSpacing: 56
    rowSpacing: 18
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter

    Column {
      spacing: 12
      // Leading zeros dim, the typed digits lit: 00:05:00 reads as five
      // minutes rather than as a number somebody has to parse.
      Digits {
        anchors.horizontalCenter: parent.horizontalCenter
        family: root.app.ui.font
        text: Watch.keypadClock(root.app.digits)
        litFrom: Watch.keypadLit(root.app.digits)
        pixelSize: Math.round(root.app.body * (root.wide ? 3.4 : 2.5))
        weight: Font.Light
        color: root.app.ui.text
        dimColor: root.app.ui.alpha(root.app.ui.muted, 0.45)
      }
      // What will run, in words: where 0:90 becomes a minute and a half before
      // anybody presses Start.
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.app.typed > 0 ? Watch.spanLabel(root.app.typed) : "Hours, minutes, seconds"
        color: root.app.typed > 0 ? root.app.ui.accent : root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
      Flow {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(root.width - 24, 340)
        spacing: 6
        Repeater {
          model: Watch.PRESETS
          delegate: Chip {
            required property int modelData
            app: root.app
            text: Watch.spanLabel(modelData * 1000)
            onClicked: root.app.keyPreset(modelData)
          }
        }
      }
      Button {
        visible: root.wide
        anchors.horizontalCenter: parent.horizontalCenter
        app: root.app
        primary: true
        text: "Start"
        enabled: root.app.typed > 0
        onClicked: root.app.timerStart()
      }
    }

    Column {
      spacing: 14
      Grid {
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 3
        spacing: 8
        Repeater {
          model: root.keypad
          delegate: Rectangle {
            id: key
            required property var modelData
            // Above the 44 px thumb floor both ways: a duration is typed in
            // the same hurry a sum is.
            width: root.wide ? 88 : 100
            height: root.wide ? 52 : 56
            radius: root.app.ui.radius + 2
            color: keyTap.pressed ? root.app.ui.pressed
              : keyTap.containsMouse ? Qt.tint(root.app.ui.surface, root.app.ui.hover)
              : modelData.key < 0 ? root.app.ui.well : root.app.ui.surface
            Accessible.role: Accessible.Button
            Accessible.name: modelData.key === -1 ? "Backspace" : modelData.text
            Text {
              anchors.centerIn: parent
              text: key.modelData.text
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: Math.round(root.app.body * 1.25)
            }
            MouseArea {
              id: keyTap
              anchors.fill: parent
              hoverEnabled: !root.app.compact
              cursorShape: Qt.PointingHandCursor
              onClicked: root.app.keyPress(key.modelData.key)
              // Held, backspace empties the entry: a six-digit mistake is six
              // taps otherwise.
              onPressAndHold: if (key.modelData.key === -1) root.app.keyClear()
            }
          }
        }
      }
      Button {
        visible: !root.wide
        anchors.horizontalCenter: parent.horizontalCenter
        app: root.app
        primary: true
        text: "Start"
        enabled: root.app.typed > 0
        onClicked: root.app.timerStart()
      }
    }
  }
}
