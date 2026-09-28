import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Habits.js" as H
import "Game.js" as Game
import "Glyphs.js" as G

// One habit: what it is, how it is going, and its history. A page of its own
// on a phone, and the pane beside the list on a desktop.
Item {
  id: root
  property var app
  property var habit: null
  // A page with a back arrow, or the pane with a close button.
  property bool paged: false

  readonly property int rev: app.revision
  readonly property int run: habit && rev >= 0 ? H.streak(habit, app.today) : 0
  readonly property real strength: habit && rev >= 0 ? H.score(habit, app.today) : 0
  readonly property var upcoming: habit && rev >= 0 ? H.nextMilestone(habit, app.today) : null
  readonly property color hue: habit ? app.habitHue(habit.colour) : app.ui.accent

  PageHeader {
    id: pageHead
    visible: root.paged
    app: root.app
    width: parent.width
    title: root.habit ? root.habit.name : ""
    subtitle: root.habit ? H.frequencyLabel(root.habit) : ""
    IconButton { app: root.app; glyph: G.edit; label: "Edit"; onClicked: root.app.editHabit(root.habit) }
    IconButton { app: root.app; glyph: KG.remove; label: "Delete"; onClicked: root.app.askDelete(root.habit) }
  }

  Item {
    id: paneHead
    visible: !root.paged
    width: parent.width
    height: 64
    Column {
      anchors.left: parent.left
      anchors.leftMargin: 20
      anchors.right: paneActions.left
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      Text {
        width: parent.width
        text: root.habit ? root.habit.name : ""
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: 19
        font.weight: Font.Bold
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: root.habit ? H.frequencyLabel(root.habit) : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
    }
    Row {
      id: paneActions
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      IconButton { app: root.app; glyph: G.edit; label: "Edit"; onClicked: root.app.editHabit(root.habit) }
      IconButton { app: root.app; glyph: KG.remove; label: "Delete"; onClicked: root.app.askDelete(root.habit) }
      IconButton { app: root.app; glyph: KG.close; label: "Close"; onClicked: root.app.selectedId = "" }
    }
  }

  Flickable {
    id: flick
    anchors.top: root.paged ? pageHead.bottom : paneHead.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: body.implicitHeight + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      x: root.paged ? root.app.ui.gutter : 20
      y: 4
      width: Math.min(flick.width - x * 2, 640)
      spacing: 16

      Card {
        visible: root.habit !== null && root.habit.question !== ""
        app: root.app
        width: parent.width
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: root.habit ? root.habit.question : ""
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
        }
      }

      // The streak, big and in the habit's own colour, and the strength under
      // it: a streak is binary and cruel, the strength drops a little for a
      // missed day and recovers as fast as it fell.
      Card {
        app: root.app
        width: parent.width
        Column {
          width: parent.width
          spacing: 4
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.run
            color: root.hue
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xxl + 8
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.run === 1 ? "DAY" : "DAY STREAK"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
            font.letterSpacing: 1
          }
          Item { width: 1; height: 8 }
          Rectangle {
            width: parent.width
            height: 8
            radius: root.app.ui.round(height)
            color: root.app.ui.well
            Rectangle {
              width: parent.width * root.strength
              height: parent.height
              radius: root.app.ui.round(height)
              color: root.hue
            }
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(root.strength * 100) + "% strength"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
        }
      }

      Card {
        app: root.app
        width: parent.width
        Repeater {
          model: {
            var h = root.habit
            if (!h || root.rev < 0) return []
            var rows = [["How often", H.frequencyLabel(h)]]
            // Something to aim at: "4 days to 30" is the same fact as a streak
            // with somewhere to go. Gone once the last one is behind you.
            if (root.upcoming)
              rows.push(["Next milestone", root.upcoming.target + " days" + (root.upcoming.away ? " — " + root.upcoming.away + " to go" : "")])
            rows.push(["Best streak", H.bestStreak(h, root.app.today) + " days"])
            rows.push(["Days kept", H.keptDays(h) + " days"])
            rows.push(["Points", String(Game.habitPoints(h))])
            // For a yes-or-no habit the total is the days kept, again.
            if (h.kind === H.MEASURABLE)
              rows.push(["Total", Math.round(H.total(h) * 100) / 100 + (h.unit ? " " + h.unit : "")])
            return rows
          }
          delegate: Item {
            required property var modelData
            width: parent.width
            height: 30
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData[0]
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: modelData[1]
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
              font.features: ({ "tnum": 1 })
            }
          }
        }
      }

      Card {
        app: root.app
        width: parent.width
        title: "History"
        Heatmap {
          app: root.app
          habit: root.habit
          // Sixteen weeks and the weekday letters across the card's width.
          cell: Math.max(8, Math.min(18, Math.floor((parent.width - 17 - 15 * 3) / 16)))
        }
      }
    }
  }
}
