import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Alarms.js" as Alarms

// The first screen: the dial, the time and the date, then the alarms. On a
// phone they are one column and the dial takes whatever the list leaves; on
// a desktop the dial stands on the left and the alarms are a list beside it.
Item {
  id: root
  property var app

  readonly property bool wide: !app.compact

  // The dial, the time in digits and the date.
  component Hero: Column {
    id: hero
    property var app
    property int dial: 132
    spacing: 6

    Face {
      id: face
      anchors.horizontalCenter: parent.horizontalCenter
      width: hero.dial
      height: hero.dial
      hours: hero.app.face.hours
      minutes: hero.app.face.minutes
      seconds: hero.app.face.seconds
      ink: hero.app.ui.text
      dim: hero.app.ui.muted
      accent: hero.app.ui.accent
      behind: hero.app.ui.bg
      // Sweeping only while it is looked at. A hand animated behind a closed
      // window is a compositor paying for nobody.
      sweeping: !hero.app.pinned && hero.app.opened && hero.app.tab === "alarm" && !hero.app.topPage
    }
    Connections {
      target: hero.app
      // The hands are put where the clock is when the window comes back, and
      // the sweep starts again from there.
      function onSummoned() { face.lock() }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 5
      Digits {
        anchors.verticalCenter: parent.verticalCenter
        family: hero.app.ui.font
        text: Alarms.timeText(new Date(hero.app.now).getHours(), new Date(hero.app.now).getMinutes(), hero.app.hour24)
        pixelSize: Math.round(hero.app.body * (hero.dial > 160 ? 3.4 : 2.6))
        weight: Font.Light
        color: hero.app.ui.text
      }
      Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        visible: !hero.app.hour24
        text: Alarms.meridiem(new Date(hero.app.now).getHours())
        color: hero.app.ui.muted
        font.family: hero.app.ui.font
        font.pixelSize: hero.app.ui.fs.sm
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: Qt.formatDate(new Date(hero.app.now), "dddd d MMMM")
      color: hero.app.ui.muted
      font.family: hero.app.ui.font
      font.pixelSize: hero.app.ui.fs.sm
    }
  }

  // Everything under the dial: the empty state, the missed note, the rows.
  component Rows: Column {
    id: rows
    property var app
    spacing: 8

    EmptyState {
      visible: !rows.app.ordered.length
      anchors.horizontalCenter: parent.horizontalCenter
      app: rows.app
      glyph: String.fromCodePoint(0xF0020)
      title: "No alarms"
      text: "An alarm here rings when the phone is awake, and says how late it is if it was not."
      actionText: "New alarm"
      onAction: rows.app.startNew()
    }

    // An alarm that did not ring, said until it is dismissed.
    Rectangle {
      visible: rows.app.missedNote.length > 0
      width: parent.width
      height: Math.max(rows.app.ui.target, noteText.implicitHeight + 20)
      radius: rows.app.ui.radius
      color: rows.app.ui.alpha(rows.app.ui.late, 0.14)
      border.width: 1
      border.color: rows.app.ui.alpha(rows.app.ui.late, 0.5)
      Text {
        id: noteText
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: rows.app.ui.target
        wrapMode: Text.Wrap
        text: rows.app.missedNote
        color: rows.app.ui.late
        font.family: rows.app.ui.font
        font.pixelSize: rows.app.ui.fs.sm
      }
      IconButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        app: rows.app
        glyph: KG.close
        color: rows.app.ui.late
        label: "Dismiss"
        onClicked: rows.app.missedNote = ""
      }
    }

    Repeater {
      model: rows.app.ordered
      delegate: AlarmRow {
        required property var modelData
        app: rows.app
        alarm: modelData
        width: rows.width
      }
    }
  }

  // ------------------------------------------------------------ phone

  Flickable {
    id: phone
    anchors.fill: parent
    visible: !root.wide
    contentWidth: width
    contentHeight: phoneCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: phoneCol
      width: phone.width

      // The dial takes the slack the list leaves, so with one alarm the clock
      // is in the middle of the screen rather than at the top of a screenful
      // of nothing -- and never less than its own height.
      Item {
        width: parent.width
        height: Math.max(236, phoneHero.implicitHeight + 24, phone.height - phoneRows.implicitHeight - 96)
        Hero {
          id: phoneHero
          app: root.app
          anchors.centerIn: parent
          width: parent.width
        }
      }
      Rows {
        id: phoneRows
        app: root.app
        x: root.app.ui.gutter
        width: parent.width - root.app.ui.gutter * 2
      }
      // Clear of the round button.
      Item { width: 1; height: 88 }
    }
  }

  // The new-alarm button where a thumb is, on a phone. On a desktop it is the
  // + in the header, and n.
  Rectangle {
    visible: !root.wide && !root.app.ringing
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 16
    width: 56
    height: 56
    radius: root.app.ui.radius
    color: fabMouse.pressed ? Qt.darker(root.app.ui.accent, 1.15) : root.app.ui.accent
    Accessible.role: Accessible.Button
    Accessible.name: "New alarm"
    Icon {
      anchors.centerIn: parent
      app: root.app
      text: KG.plus
      size: 26
      color: root.app.ui.inkOnAccent
    }
    MouseArea {
      id: fabMouse
      anchors.fill: parent
      onClicked: root.app.startNew()
    }
  }

  // ------------------------------------------------------------ desktop

  Item {
    anchors.fill: parent
    visible: root.wide

    Item {
      id: left
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.max(300, parent.width * 0.42)
      Hero {
        app: root.app
        dial: Math.min(260, left.width - 60, left.height - 180)
        anchors.centerIn: parent
        width: parent.width
      }
    }

    Flickable {
      anchors.left: left.right
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.rightMargin: 24
      contentWidth: width
      contentHeight: deskRows.implicitHeight + 24
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Rows {
        id: deskRows
        app: root.app
        y: 4
        width: parent.width
      }
    }
  }
}
