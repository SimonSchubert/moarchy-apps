import QtQuick
import "kit"
import "Store.js" as S
import "Tictactoe.js" as T

// Games against the computer, by difficulty.
//
// The headline figure is not wins, and that is the one honest thing this has
// to do. Against Perfect there are no wins to be had -- the game is drawn with
// correct play from both sides, every time -- so a win percentage at the top
// would tell somebody they are bad at a game they have in fact solved. The
// figure is the longest run without losing, which can be got better at
// against all three levels.
Column {
  id: root
  property var app
  property var game: S.fresh()
  readonly property var totals: S.totals(game)

  spacing: 14

  Row {
    width: parent.width
    spacing: 8
    Repeater {
      model: [["Played", root.totals.played], ["Won", root.totals.won], ["Unbeaten", root.totals.best]]
      delegate: Rectangle {
        required property var modelData
        width: (root.width - 16) / 3
        height: 72
        radius: root.app.ui.radius
        color: root.app.ui.surface
        border.width: 1
        border.color: root.app.ui.line
        Column {
          anchors.centerIn: parent
          spacing: 2
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData[1]
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xl
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData[0]
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
            font.capitalization: Font.AllUppercase
            font.letterSpacing: root.app.ui.tracking
          }
        }
      }
    }
  }

  Card {
    app: root.app
    width: parent.width
    title: "By difficulty"
    Repeater {
      model: T.LEVELS
      delegate: Item {
        id: row
        required property var modelData
        readonly property var entry: S.recordFor(root.game, modelData.key)
        width: parent.width
        height: 44
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - best.implicitWidth - 8
          spacing: 2
          Text {
            text: row.modelData.label
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: Font.Bold
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: row.entry.played
              ? row.entry.won + " won · " + row.entry.lost + " lost · " + row.entry.drawn + " drawn"
              : "Not played yet"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
        }
        Text {
          id: best
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: row.entry.played ? row.entry.best + " unbeaten" : "—"
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.Wrap
    text: "Perfect cannot be beaten — with correct play on both sides this game is always drawn. A run of draws against it is the result."
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }
}
