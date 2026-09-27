pragma ComponentBehavior: Bound

import QtQuick
import "kit"
import "Glyphs.js" as G
import "Dates.js" as Dates

// The same events as one list from today forward: the other question a
// calendar is opened for. A month's name where the month turns, and the
// weekday and date down the left.
Flickable {
  id: root
  property var app

  clip: true
  contentWidth: width
  contentHeight: col.height + 24
  boundsBehavior: Flickable.StopAtBounds

  Column {
    id: col
    width: parent.width
    topPadding: 4

    Repeater {
      // Four hundred days are walked to build this, and none of them matter
      // until the window is up.
      model: root.app.opened ? root.app.agenda : []

      delegate: Item {
        id: group
        required property var modelData
        required property int index

        readonly property bool newMonth: group.index === 0
          || Dates.monthOfDay(group.modelData.iso) !== Dates.monthOfDay(root.app.agenda[group.index - 1].iso)
        readonly property bool isToday: group.modelData.iso === root.app.today

        width: col.width
        height: rows.height + 16 + (group.newMonth ? monthMark.height + 12 : 0)

        Text {
          id: monthMark
          anchors.top: parent.top
          anchors.topMargin: 6
          x: root.app.ui.gutter + 4
          visible: group.newMonth
          text: Dates.MONTHS[Dates.monthOf(Dates.monthOfDay(group.modelData.iso)) - 1].toUpperCase()
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          font.weight: Font.DemiBold
          font.letterSpacing: 1.2
        }

        Column {
          id: rail
          anchors.top: group.newMonth ? monthMark.bottom : parent.top
          anchors.topMargin: group.newMonth ? 10 : 8
          x: root.app.ui.gutter
          width: 46
          spacing: -2
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Dates.DAYS_SHORT[Dates.weekday(group.modelData.iso)]
            color: group.isToday ? root.app.ui.accent : root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
            font.weight: Font.DemiBold
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Dates.parts(group.modelData.iso).d
            color: group.isToday ? root.app.ui.accent : root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: 24
            font.weight: group.isToday ? Font.DemiBold : Font.Normal
          }
        }

        Column {
          id: rows
          anchors.top: rail.top
          anchors.left: rail.right
          anchors.leftMargin: 8
          anchors.right: parent.right
          anchors.rightMargin: root.app.ui.gutter
          spacing: 6

          Repeater {
            model: group.modelData.items
            delegate: EventRow {
              required property var modelData
              app: root.app
              width: rows.width
              entry: modelData
              selected: !!root.app.draft && root.app.draft.id === modelData.id
              onClicked: {
                root.app.selected = group.modelData.iso
                root.app.startEdit(modelData)
              }
            }
          }
        }
      }
    }

    Item {
      width: col.width
      height: ahead.implicitHeight + 60
      visible: root.app.agenda.length === 0
      EmptyState {
        id: ahead
        app: root.app
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        glyph: G.agenda
        title: "Nothing ahead"
        text: root.app.events.length ? "Nothing in the next year, anyway." : "The plus puts something in the day."
      }
    }
  }
}
