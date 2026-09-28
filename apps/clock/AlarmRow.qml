import QtQuick
import "Alarms.js" as Alarms

// One alarm: its time, what it is for and how often, when it next rings, and
// its switch. The card opens the editor; the switch is its own target.
Rectangle {
  id: row
  property var app
  property var alarm: ({})

  readonly property double fires: Alarms.nextFire(alarm, app.now)
  readonly property bool on: !!alarm.enabled

  height: 88
  radius: app.ui.radius
  color: tap.pressed ? Qt.tint(app.ui.surface, app.ui.pressed)
    : tap.containsMouse ? Qt.tint(app.ui.surface, app.ui.hover)
    : on ? app.ui.surface : row.app.ui.offCard
  border.width: 1
  border.color: app.ui.line
  Accessible.role: Accessible.Button
  Accessible.name: Alarms.timeText(alarm.hour, alarm.minute, app.hour24) + (alarm.label ? ", " + alarm.label : "")

  MouseArea {
    id: tap
    anchors.fill: parent
    anchors.rightMargin: 62
    hoverEnabled: !row.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: row.app.edit(row.alarm.id)
  }

  Column {
    anchors.left: parent.left
    anchors.leftMargin: 16
    anchors.right: toggle.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1

    Row {
      spacing: 4
      Digits {
        anchors.verticalCenter: parent.verticalCenter
        family: row.app.ui.font
        text: Alarms.timeText(row.alarm.hour, row.alarm.minute, row.app.hour24)
        pixelSize: Math.round(row.app.body * 1.7)
        weight: Font.Normal
        color: row.on ? row.app.ui.text : row.app.ui.muted
      }
      Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        visible: !row.app.hour24
        text: Alarms.meridiem(row.alarm.hour)
        color: row.app.ui.muted
        font.family: row.app.ui.font
        font.pixelSize: row.app.ui.fs.sm
      }
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: {
        var repeat = Alarms.repeatLabel(row.alarm.days || [])
        return row.alarm.label ? row.alarm.label + " · " + repeat : repeat
      }
      color: row.app.ui.muted
      opacity: row.on ? 1 : 0.6
      font.family: row.app.ui.font
      font.pixelSize: row.app.ui.fs.sm
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: {
        if (!row.on) return "Off"
        if (row.alarm.snoozed > row.app.now) return "Snoozed, again " + Alarms.untilLabel(row.fires - row.app.now)
        return Alarms.whichDay(row.fires, row.app.now) + ", " + Alarms.untilLabel(row.fires - row.app.now)
      }
      color: row.on ? row.app.ui.accent : row.app.ui.muted
      opacity: row.on ? 1 : 0.6
      font.family: row.app.ui.font
      font.pixelSize: row.app.ui.fs.sm
    }
  }

  Switch {
    id: toggle
    anchors.right: parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    checked: row.on
    accent: row.app.ui.accent
    knobInk: row.app.ui.inkOnAccent
    dim: row.app.ui.muted
    corner: row.app.ui.radius
    onToggled: row.app.toggleAlarm(row.alarm.id)
  }
}
