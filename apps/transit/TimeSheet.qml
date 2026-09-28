import QtQuick
import "Api.mjs" as Api

// When to travel: leave now, leave at, or arrive by, on one of the next seven
// days. Wheels for the hour and the minute, in five-minute steps.
Item {
  id: root
  property var app

  property bool arriveBy: false
  property int day: 0          // days from today
  property int hour: 8
  property int minute: 0       // a multiple of 5

  function load() {
    var q = app.query
    var t = q.time || Date.now() + 5 * 60000
    var d = new Date(t)
    var today = new Date(); today.setHours(0, 0, 0, 0)
    var that = new Date(d); that.setHours(0, 0, 0, 0)
    arriveBy = !!q.arriveBy
    day = Math.max(0, Math.min(6, Math.round((that - today) / 86400000)))
    hour = d.getHours()
    minute = Math.min(55, Math.round(d.getMinutes() / 5) * 5)
    hours.positionViewAtIndex(hour, ListView.Center)
    hours.currentIndex = hour
    mins.positionViewAtIndex(minute / 5, ListView.Center)
    mins.currentIndex = minute / 5
  }

  function chosen() {
    var d = new Date()
    d.setHours(0, 0, 0, 0)
    d.setDate(d.getDate() + day)
    d.setHours(hour, minute, 0, 0)
    return d.getTime()
  }

  function apply(now) {
    app.query = Object.assign({}, app.query, { time: now ? 0 : chosen(), arriveBy: now ? false : arriveBy })
    app.timeOpen = false
    if (app.resultsOpen) app.search()
  }

  onVisibleChanged: if (visible) load()

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)
    MouseArea { anchors.fill: parent; onClicked: root.app.timeOpen = false }
  }

  Rectangle {
    id: sheet
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(parent.width, 520)
    height: col.implicitHeight + 32
    radius: 20
    color: root.app.ui.bg
    border.width: root.app.compact ? 0 : 1
    border.color: root.app.ui.border
    // Square where it meets the bottom edge.
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 20; color: parent.color; visible: root.app.compact }
    MouseArea { anchors.fill: parent }

    Column {
      id: col
      x: 18
      y: 16
      width: parent.width - 36
      spacing: 14

      Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 36; height: 4; radius: 2; color: root.app.ui.divider }

      // Leave at / arrive by.
      Rectangle {
        width: parent.width
        height: 40
        radius: 20
        color: root.app.ui.surface
        Row {
          anchors.fill: parent
          anchors.margins: 3
          Repeater {
            model: [{ k: false, l: "Leave at" }, { k: true, l: "Arrive by" }]
            delegate: Rectangle {
              required property var modelData
              width: (parent.width) / 2
              height: parent.height
              radius: height / 2
              color: root.arriveBy === modelData.k ? root.app.ui.bg : "transparent"
              border.width: root.arriveBy === modelData.k ? 1 : 0
              border.color: root.app.ui.border
              Text {
                anchors.centerIn: parent
                text: parent.modelData.l
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
                font.weight: root.arriveBy === parent.modelData.k ? Font.DemiBold : Font.Normal
              }
              MouseArea { anchors.fill: parent; onClicked: root.arriveBy = parent.modelData.k }
            }
          }
        }
      }

      // The next seven days.
      Flow {
        id: days
        width: parent.width
        spacing: 6
        Repeater {
          model: 7
          delegate: Chip {
            required property int index
            app: root.app
            hpad: 20
            text: Api.dayLabel(Date.now() + index * 86400000, Date.now())
            selected: root.day === index
            onClicked: root.day = index
          }
        }
      }

      // Hour : minute.
      Item {
        width: parent.width
        height: 150

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: 44
          radius: 12
          color: root.app.ui.accentSoft
        }

        Wheel {
          id: hours
          x: parent.width / 2 - width - 14
          width: 80
          height: parent.height
          app: root.app
          rows: 24
          format: function (i) { return root.app.store.clock24 ? (i < 10 ? "0" + i : "" + i) : ((i % 12 || 12) + (i < 12 ? " am" : " pm")) }
          onPicked: function (i) { root.hour = i }
        }
        Text {
          anchors.centerIn: parent
          text: ":"
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: 26
          font.weight: Font.Bold
        }
        Wheel {
          id: mins
          x: parent.width / 2 + 14
          width: 80
          height: parent.height
          app: root.app
          rows: 12
          format: function (i) { var m = i * 5; return m < 10 ? "0" + m : "" + m }
          onPicked: function (i) { root.minute = i * 5 }
        }
      }

      Row {
        width: parent.width
        spacing: 10
        Button {
          width: (parent.width - 10) / 2
          app: root.app
          text: "Now"
          glyph: Api.GLYPH.clock
          onClicked: root.apply(true)
        }
        Button {
          width: (parent.width - 10) / 2
          app: root.app
          primary: true
          text: "Done"
          onClicked: root.apply(false)
        }
      }
    }
  }
}
