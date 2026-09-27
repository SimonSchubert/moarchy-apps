// One month, as a grid of days you can tap.
//
// Its own file because it is drawn three ways: the month screen on a phone,
// with a dot under a date for each thing on it; the same screen on a desktop,
// where a day is big enough to name what is on it; and inside the editor,
// where picking a date is the same grid made smaller. A date picker that does
// not look like the calendar it came from is two things to learn instead of
// one.
//
// It holds no state. The selected day, today and the events all come in as
// properties.
pragma ComponentBehavior: Bound

import QtQuick
import "Dates.js" as Dates
import "Events.js" as Events

Item {
  id: root

  property var app
  property int year: 1970
  property int month: 1
  // 0 Sunday, 1 Monday -- whichever the week starts on here.
  property int weekStart: 1

  property string today: ""
  property string selected: ""

  property var events: []
  property int revision: 0

  // The editor's copy: smaller rows, no dots, no weekend wash.
  property bool compact: false
  // The desktop's: a day is a box with the names of what is on it.
  property bool large: false

  signal picked(string iso)
  signal opened(var entry)

  readonly property var cells: Dates.grid(root.year, root.month, root.weekStart)
  readonly property var dots: {
    var r = root.revision
    return root.compact || root.large ? [] : Events.marks(root.events, root.cells)
  }
  readonly property var days: {
    var r = root.revision
    if (!root.large) return []
    var out = []
    for (var i = 0; i < root.cells.length; i++) out.push(Events.onDay(root.events, root.cells[i].iso))
    return out
  }

  readonly property var labels: Dates.weekdayLabels(root.weekStart, root.large ? "short" : "initial")
  readonly property real cellWidth: root.width / 7
  readonly property real headerHeight: root.compact ? 20 : root.large ? 30 : 26
  readonly property real cellHeight: (root.height - root.headerHeight) / Dates.ROWS
  readonly property real disc: Math.min(root.cellWidth - 8,
                                        root.compact ? root.cellHeight - 6
                                          : root.large ? 28 : root.cellHeight - 12)

  function ink(cell) {
    if (cell.iso === root.selected)
      return root.selected === root.today ? root.app.ui.inkOnAccent : root.app.ui.text
    // A day either side of this month is still a day, so it is dimmed rather
    // than left out -- far enough back to read as somewhere else, near enough
    // to aim at when the month has just turned.
    if (!cell.inMonth) return root.app.ui.alpha(root.app.ui.muted, 0.55)
    if (cell.iso === root.today) return root.app.ui.accent
    return root.app.ui.text
  }

  // The weekend, one shade off the window. Small enough that nobody sees a
  // colour, large enough that the week reads as a week.
  readonly property color weekendWash: root.app.ui.alpha(root.app.ui.text, root.app.ui.dark ? 0.05 : 0.03)

  // --- the weekday row ------------------------------------------------------

  Row {
    id: header
    width: root.width
    height: root.headerHeight

    Repeater {
      model: root.labels

      delegate: Item {
        id: head
        required property int index
        required property string modelData

        width: root.cellWidth
        height: header.height

        Text {
          anchors.centerIn: parent
          text: root.large ? head.modelData.toUpperCase() : head.modelData
          color: Dates.isWeekend((head.index + root.weekStart) % 7)
                 ? root.app.ui.alpha(root.app.ui.muted, 0.7) : root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          font.weight: Font.DemiBold
          font.letterSpacing: 1.2
        }
      }
    }
  }

  // --- the weekend columns --------------------------------------------------

  // Behind the grid rather than inside a cell, so that it is one column of
  // colour down the screen instead of six rectangles that happen to line up.
  Row {
    anchors.top: header.bottom
    width: root.width
    height: root.cellHeight * Dates.ROWS
    visible: !root.compact

    Repeater {
      model: 7

      delegate: Rectangle {
        id: column
        required property int index

        width: root.cellWidth
        height: root.cellHeight * Dates.ROWS
        radius: root.app.ui.radius
        color: Dates.isWeekend((column.index + root.weekStart) % 7) ? root.weekendWash : "transparent"
      }
    }
  }

  // --- the days -------------------------------------------------------------

  Grid {
    anchors.top: header.bottom
    width: root.width
    columns: 7

    Repeater {
      model: root.cells

      delegate: Item {
        id: cell
        required property var modelData
        required property int index

        readonly property bool isToday: cell.modelData.iso === root.today
        readonly property bool isSelected: cell.modelData.iso === root.selected
        readonly property var colourList: root.dots.length > cell.index ? root.dots[cell.index] : []
        readonly property var entries: root.days.length > cell.index ? root.days[cell.index] : []

        width: root.cellWidth
        height: root.cellHeight

        Accessible.role: Accessible.Button
        Accessible.name: Dates.fullDayLabel(cell.modelData.iso)
              + (cell.colourList.length ? ", " + cell.colourList.length + " events" : "")
        Accessible.onPressAction: root.picked(cell.modelData.iso)

        // The desktop's day box: a hover and the selection, drawn round the
        // whole day rather than its number.
        Rectangle {
          visible: root.large
          anchors.fill: parent
          anchors.margins: 2
          radius: root.app.ui.radius
          color: cell.isSelected ? root.app.ui.selected : hover.hovered ? root.app.ui.hover : "transparent"
          border.width: cell.isSelected ? 1 : 0
          border.color: root.app.ui.accent
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.picked(cell.modelData.iso)
          onDoubleClicked: if (root.large && cell.entries.length) root.opened(cell.entries[0])
        }
        HoverHandler { id: hover; enabled: root.large }

        Rectangle {
          id: pip
          x: root.large ? 6 : Math.round((cell.width - width) / 2)
          y: root.compact ? Math.round((cell.height - height) / 2) : root.large ? 5 : 3
          width: root.disc
          height: root.disc
          radius: width / 2

          color: {
            if (root.large) return cell.isToday ? root.app.ui.accent : "transparent"
            if (cell.isSelected) return cell.isToday ? root.app.ui.accent : root.app.ui.surfaceHigh
            // Today is a wash of the accent until it is chosen, and the
            // accent itself once it is.
            return cell.isToday ? root.app.ui.accentSoft : "transparent"
          }
          Behavior on color { ColorAnimation { duration: 120 } }

          Text {
            anchors.centerIn: parent
            text: cell.modelData.day
            color: root.large && cell.isToday ? root.app.ui.inkOnAccent : root.ink(cell.modelData)
            font.family: root.app.ui.font
            font.pixelSize: root.compact ? root.app.ui.fs.sm : root.app.ui.fs.md
            font.weight: cell.isToday || cell.isSelected ? Font.DemiBold : Font.Normal
          }
        }

        // What is on that day, one dot an event: four dots in four colours is
        // the difference between the dentist and four meetings.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: pip.bottom
          anchors.topMargin: 2
          spacing: 3
          visible: !root.compact && !root.large

          Repeater {
            model: cell.colourList

            delegate: Rectangle {
              required property string modelData

              width: 5
              height: 5
              radius: 2.5
              color: root.app.eventColour(modelData)
              opacity: cell.modelData.inMonth ? 1.0 : 0.45
            }
          }
        }

        // On a desktop, the names themselves, as many as fit.
        Column {
          visible: root.large
          anchors.top: pip.bottom
          anchors.topMargin: 3
          x: 4
          width: parent.width - 8
          spacing: 2
          readonly property int room: Math.max(0, Math.floor((cell.height - root.disc - 12) / 20))

          Repeater {
            model: cell.entries.slice(0, Math.max(0, cell.entries.length > parent.room ? parent.room - 1 : parent.room))
            delegate: Rectangle {
              id: chip
              required property var modelData
              width: parent.width
              height: 18
              radius: 4
              color: root.app.eventWash(chip.modelData.colour)
              opacity: cell.modelData.inMonth ? 1 : 0.55
              Rectangle { width: 3; height: parent.height - 6; y: 3; x: 3; radius: 1.5; color: root.app.eventColour(chip.modelData.colour) }
              Text {
                x: 10
                width: parent.width - 12
                anchors.verticalCenter: parent.verticalCenter
                text: (chip.modelData.allDay ? "" : Dates.formatTime(chip.modelData.start) + " ") + chip.modelData.title
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xs
                elide: Text.ElideRight
              }
              MouseArea {
                anchors.fill: parent
                onClicked: { root.picked(cell.modelData.iso); root.opened(chip.modelData) }
              }
            }
          }
          Text {
            visible: cell.entries.length > parent.room && parent.room > 0
            x: 4
            text: "+" + (cell.entries.length - Math.max(0, parent.room - 1)) + " more"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
        }
      }
    }
  }
}
