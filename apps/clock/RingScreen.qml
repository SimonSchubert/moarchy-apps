import QtQuick
import "kit"
import "Alarms.js" as Alarms

// Something is going off. Over everything, header and tabs included, and a
// back gesture does not take it down: an alarm a gesture can lose by accident
// is not an alarm. Two large buttons, Snooze and Stop.
Rectangle {
  id: root
  property var app

  readonly property bool timerRing: app.ringing !== null && app.ringing.kind === "timer"
  readonly property color hue: timerRing ? app.ui.good : app.ui.accent

  parent: app ? app.overlay : null
  anchors.fill: parent
  visible: app.ringing !== null
  z: 20
  color: app.ui.bg

  // Under the content, so nothing behind this screen can be pressed through.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
  }

  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Math.round(parent.height * 0.13)
    width: Math.min(parent.width, 520)
    spacing: 10

    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 108
      height: 108

      // One ring, breathing. A phone that is ringing is already moving in
      // somebody's hand; a shaking bell is a repaint per frame nobody needs.
      Rectangle {
        id: pulse
        anchors.centerIn: parent
        width: 88
        height: 88
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: root.hue
        SequentialAnimation {
          running: root.visible && !root.app.pinned
          loops: Animation.Infinite
          ParallelAnimation {
            NumberAnimation { target: pulse; property: "scale"; from: 0.82; to: 1.2; duration: 1100; easing.type: Easing.OutQuad }
            NumberAnimation { target: pulse; property: "opacity"; from: 0.9; to: 0; duration: 1100 }
          }
        }
      }
      Rectangle {
        anchors.centerIn: parent
        width: 74
        height: 74
        radius: width / 2
        color: root.hue
        Icon {
          anchors.centerIn: parent
          app: root.app
          text: String.fromCodePoint(root.timerRing ? 0xF051F : 0xF0020)
          size: 34
          color: root.app.ui.bg
        }
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: root.app.ringing ? root.app.ringing.label : ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.lg + 2
      font.weight: Font.DemiBold
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 5
      Digits {
        anchors.verticalCenter: parent.verticalCenter
        family: root.app.ui.font
        text: root.app.ringing ? root.app.ringing.time : ""
        pixelSize: Math.round(root.app.body * 3.4)
        weight: Font.Light
        color: root.app.ui.text
      }
      Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        visible: !root.app.hour24 && !root.timerRing && root.app.ringing !== null
        text: root.app.ringing ? Alarms.meridiem(new Date(root.app.ringing.at).getHours()) : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
    }

    // The two sentences this screen owes: how late it is -- the whole of what
    // this app can honestly do about a phone that was asleep -- and that it is
    // making no sound, if it is not.
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      visible: text.length > 0
      text: root.app.ringLate()
      color: root.app.ui.late
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
    }
    Text {
      x: 24
      width: parent.width - 48
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      // Only the two a person can do something about. `quiet` is the
      // screenshot harness's.
      visible: root.app.mute || !!root.app.clockPrefs.silent
      text: root.app.clockPrefs.silent ? "Set to ring on the screen only." : "Nothing on this machine could play the alarm tone."
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
    }
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 48 + root.app.bottomInset
    spacing: 14

    Button {
      visible: !root.timerRing
      app: root.app
      implicitHeight: 62
      implicitWidth: 170
      text: "Snooze " + Alarms.SNOOZE_MINUTES + " min"
      onClicked: root.app.snoozeRing()
    }
    Button {
      app: root.app
      primary: true
      tint: root.hue
      implicitHeight: 62
      implicitWidth: root.timerRing ? 220 : 130
      text: "Stop"
      onClicked: root.app.stopRing()
    }
  }
}
