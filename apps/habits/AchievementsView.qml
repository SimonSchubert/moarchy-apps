import QtQuick
import "kit"
import "Game.js" as Game
import "Glyphs.js" as G

// Every badge, earned or not, and the level they add up to. A locked badge is
// shown rather than hidden: a grid with gaps in it says what there is to aim
// at, and one that only shows what you already have says nothing at all.
Flickable {
  id: root
  property var app

  readonly property int points: app.revision >= 0 ? Game.totalPoints(app.habits) : 0
  readonly property var level: Game.levelFor(points)
  readonly property int earnedCount: {
    var n = 0
    var all = Game.keys()
    for (var i = 0; i < all.length; i++) if (app.achievements[all[i]] !== undefined) n += 1
    return n
  }
  readonly property int columns: width >= 900 ? 5 : width >= 560 ? 4 : width >= 420 ? 3 : 2

  contentWidth: width
  contentHeight: body.implicitHeight + 32
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  Column {
    id: body
    x: root.app.ui.gutter
    y: 4
    width: root.width - x * 2
    spacing: 16

    Card {
      app: root.app
      width: parent.width
      Column {
        width: parent.width
        spacing: 6
        Text {
          text: "Level " + root.level.level + " · " + root.level.name
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.lg + 2
          font.weight: Font.Bold
        }
        Rectangle {
          width: parent.width
          height: 8
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
          wrapMode: Text.Wrap
          text: root.points + " points · " + root.earnedCount + " of " + Game.ACHIEVEMENTS.length + " earned"
            + (root.level.toGo === null ? "" : " · " + root.level.toGo + " to the next level")
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }
    }

    SectionTitle {
      app: root.app
      text: "Achievements"
      note: root.earnedCount + " of " + Game.ACHIEVEMENTS.length + " earned"
    }

    Grid {
      id: grid
      width: parent.width
      columns: root.columns
      spacing: 10
      readonly property real tile: (width - (columns - 1) * spacing) / columns

      Repeater {
        model: Game.ACHIEVEMENTS
        delegate: Rectangle {
          id: badge
          required property var modelData
          readonly property string earnedOn: root.app.achievements[modelData[0]] || ""
          readonly property bool earned: earnedOn !== ""
          width: grid.tile
          height: 128
          radius: root.app.ui.radius
          color: earned ? root.app.ui.surfaceHigh : root.app.ui.surface
          border.width: 1
          border.color: earned ? root.app.ui.alpha(root.app.ui.warn, 0.6) : root.app.ui.line
          Accessible.role: Accessible.StaticText
          Accessible.name: modelData[1] + (earned ? ", earned " + earnedOn : ", " + modelData[2])

          Column {
            anchors.centerIn: parent
            width: parent.width - 16
            spacing: 4
            Icon {
              anchors.horizontalCenter: parent.horizontalCenter
              app: root.app
              text: badge.earned ? G.star : G.starOutline
              size: 26
              color: badge.earned ? root.app.ui.warn : root.app.ui.muted
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: badge.modelData[1]
              color: badge.earned ? root.app.ui.text : root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
              font.weight: Font.Bold
              elide: Text.ElideRight
            }
            // Earned once and never lost, so the date it was earned is worth
            // more than the condition once it is behind you.
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
              text: badge.earned ? "Earned " + badge.earnedOn : badge.modelData[2]
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xs
            }
          }
        }
      }
    }
  }
}
