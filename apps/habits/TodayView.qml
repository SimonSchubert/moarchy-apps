import QtQuick
import "kit"
import "Habits.js" as H
import "Game.js" as Game

// The screen people open: today's ring and the running level, then every
// habit with its last few days to tick. On a desktop wide enough, the habit
// picked opens beside the list rather than over it.
Item {
  id: root
  property var app

  readonly property bool split: app.splitDetail
  readonly property var days: H.recentDays(app.compact ? H.STRIP_DAYS : 7, app.today)
  readonly property var progress: app.revision >= 0 ? H.todayProgress(app.habits, app.today) : { done: 0, due: 0 }
  readonly property int points: app.revision >= 0 ? Game.totalPoints(app.habits) : 0
  readonly property var level: Game.levelFor(points)

  function ensureVisible(index) {
    var row = rows.itemAt(index)
    if (!row) return
    var y = row.mapToItem(list.contentItem, 0, 0).y
    if (y < list.contentY) list.contentY = y
    else if (y + row.height > list.contentY + list.height) list.contentY = y + row.height - list.height
  }

  Flickable {
    id: list
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: root.split ? parent.width - pane.width : parent.width
    contentWidth: width
    contentHeight: body.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    visible: root.app.shownHabits.length > 0

    Column {
      id: body
      x: root.app.ui.gutter
      y: 4
      width: list.width - x * 2
      spacing: 12

      // Two different measurements, so two different shapes: the ring is
      // today and resets every night, the bar is everything and never goes
      // down.
      Card {
        app: root.app
        width: parent.width
        Row {
          width: parent.width
          spacing: 16
          TodayRing {
            app: root.app
            done: root.progress.done
            due: root.progress.due
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 80
            spacing: 5
            Text {
              width: parent.width
              text: root.level.name
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.lg
              font.weight: Font.Bold
              elide: Text.ElideRight
            }
            Rectangle {
              width: parent.width
              height: 6
              radius: root.app.ui.round(height)
              color: root.app.ui.well
              Rectangle {
                height: parent.height
                radius: root.app.ui.round(height)
                color: root.app.ui.accent
                width: parent.width * (root.level.toGo === null ? 1
                  : root.level.into / Math.max(1, root.level.into + root.level.toGo))
              }
            }
            Text {
              width: parent.width
              text: root.points + " points" + (root.level.toGo === null ? "" : " · " + root.level.toGo + " to go")
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
              elide: Text.ElideRight
            }
          }
        }
      }

      // The days the rows offer, oldest on the left and today on the right,
      // where a thumb rests: the weekday, and the date, because a weekday
      // letter repeats every seven and gives no purchase on where you are.
      Item {
        width: parent.width
        height: 30
        Row {
          anchors.right: parent.right
          anchors.rightMargin: 4
          Repeater {
            model: root.days
            delegate: Column {
              required property var modelData
              width: root.app.ui.target
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: H.WEEKDAYS[H.weekday(modelData)]
                color: modelData === root.app.today ? root.app.ui.accent : root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xs
                font.weight: Font.Bold
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parseInt(modelData.slice(8), 10)
                color: modelData === root.app.today ? root.app.ui.accent : root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xs
              }
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: rowsCol.implicitHeight + 8
        radius: root.app.ui.radius
        color: root.app.ui.surface
        border.width: 1
        border.color: root.app.ui.line
        Column {
          id: rowsCol
          x: 4
          y: 4
          width: parent.width - 8
          Repeater {
            id: rows
            model: root.app.shownHabits
            delegate: HabitRow {
              required property var modelData
              required property int index
              app: root.app
              width: rowsCol.width
              habit: modelData
              days: root.days
              selected: (root.split && root.app.selectedId === modelData.id)
                || (!root.app.compact && root.app.cursor === index && root.app.selectedId === "")
              onOpened: root.app.openHabit(modelData.id)
            }
          }
        }
      }
    }
  }

  Rectangle {
    id: pane
    visible: root.split
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: root.split ? Math.min(460, parent.width * 0.45) : 0
    color: root.app.ui.surface
    DetailView {
      anchors.fill: parent
      visible: root.app.selectedHabit !== null
      app: root.app
      habit: root.app.selectedHabit
      paged: false
    }
    EmptyState {
      anchors.centerIn: parent
      visible: root.app.selectedHabit === null
      app: root.app
      glyph: root.app.todayGlyph
      title: "Pick a habit"
      text: "Its streak, its strength and sixteen weeks of history open here."
    }
  }

  EmptyState {
    anchors.centerIn: parent
    visible: root.app.shownHabits.length === 0 && root.app.loaded
    app: root.app
    glyph: root.app.todayGlyph
    title: "No habits yet"
    text: "Add something you want to do regularly. Tap a day to mark it done."
    actionText: "Add a habit"
    onAction: root.app.newHabit()
  }
}
