import QtQuick
import "kit"
import "Trivia.js" as T
import "Store.js" as S
import "Glyphs.js" as G

// How you do: every answer counted as it was given, by difficulty and by
// category, and the last rounds with their scores.
//
// The headline is the share of answers right, not rounds won -- there is no
// winning a quiz alone -- and the longest run of right answers, which is the
// one figure a round of hard questions can still improve.
Column {
  id: root
  property var app
  property var book: S.fresh()
  readonly property var stats: book.stats
  readonly property var played: S.playedCategories(book)
  // Boxes inside the desktop's pane are a step down from it; on a phone
  // they are the raised ones on the page.
  readonly property color fill: app.compact ? app.ui.surface : app.ui.bg

  spacing: 14

  component Bar: Rectangle {
    property real share: 0
    property color tone: root.app.ui.accent
    height: 4
    radius: root.app.ui.radius > 0 ? 2 : 0
    color: root.app.ui.well
    Rectangle {
      width: parent.width * Math.max(0, Math.min(1, parent.share))
      height: parent.height
      radius: parent.radius
      color: parent.tone
    }
  }

  Row {
    width: parent.width
    spacing: 8
    Repeater {
      model: [
        [String(root.stats.answered), "Answered"],
        [root.stats.answered ? T.percent(root.stats.right, root.stats.answered) + "%" : "—", "Right"],
        [String(root.stats.bestStreak), "Best run"]
      ]
      delegate: Rectangle {
        required property var modelData
        width: (root.width - 16) / 3
        height: 72
        radius: root.app.ui.radius
        color: root.fill
        border.width: 1
        border.color: root.app.ui.line
        Column {
          anchors.centerIn: parent
          spacing: 2
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData[0]
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xl
            font.weight: Font.Bold
            font.features: ({ "tnum": 1 })
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData[1]
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

  Text {
    width: parent.width
    wrapMode: Text.Wrap
    visible: root.stats.answered > 0
    text: root.stats.rounds + (root.stats.rounds === 1 ? " round" : " rounds") + " played"
      + (root.stats.sweeps ? ", " + root.stats.sweeps + " without a wrong answer" : "")
      + (root.stats.streak >= 2 ? ". On a run of " + root.stats.streak + " right now." : ".")
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }

  Text {
    width: parent.width
    wrapMode: Text.Wrap
    visible: root.stats.answered === 0
    text: "Nothing answered yet. Every answer is counted here the moment it is given, by difficulty and by category."
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }

  Card {
    visible: root.stats.answered > 0
    app: root.app
    width: parent.width
    title: "By difficulty"
    color: root.fill
    Repeater {
      model: ["easy", "medium", "hard"]
      delegate: Column {
        id: level
        required property string modelData
        readonly property var tally: root.stats.byDifficulty[modelData]
        width: parent.width
        spacing: 6
        Item {
          width: parent.width
          height: 18
          Text {
            text: T.difficultyLabel(level.modelData)
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: Font.Bold
          }
          Text {
            anchors.right: parent.right
            text: level.tally.answered ? T.percent(level.tally.right, level.tally.answered) + "% of " + level.tally.answered : "—"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            font.features: ({ "tnum": 1 })
          }
        }
        Bar {
          width: parent.width
          share: level.tally.answered ? level.tally.right / level.tally.answered : 0
          tone: root.app.difficultyTone(level.modelData)
        }
      }
    }
  }

  Card {
    visible: root.played.length > 0
    app: root.app
    width: parent.width
    title: "By category"
    trailing: root.played.length + " of " + (T.CATEGORIES.length - 1)
    color: root.fill
    Repeater {
      model: root.played
      delegate: Item {
        id: row
        required property var modelData
        readonly property var category: T.category(modelData.id)
        width: parent.width
        height: 40
        Icon {
          id: rowGlyph
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          text: row.category.glyph
          size: 16
          color: root.app.tone(row.modelData.id)
        }
        Column {
          anchors.left: rowGlyph.right
          anchors.leftMargin: 8
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5
          Item {
            width: parent.width
            height: 16
            Text {
              width: parent.width - share.implicitWidth - 8
              elide: Text.ElideRight
              text: row.category.name
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
            }
            Text {
              id: share
              anchors.right: parent.right
              text: T.percent(row.modelData.right, row.modelData.answered) + "% of " + row.modelData.answered
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
              font.features: ({ "tnum": 1 })
            }
          }
          Bar {
            width: parent.width
            share: row.modelData.right / row.modelData.answered
            tone: root.app.tone(row.modelData.id)
          }
        }
      }
    }
  }

  Card {
    visible: root.book.recent.length > 0
    app: root.app
    width: parent.width
    title: "Recent rounds"
    color: root.fill
    Repeater {
      model: root.book.recent.slice(0, 6)
      delegate: Item {
        id: recent
        required property var modelData
        width: parent.width
        height: 36
        Icon {
          id: recentGlyph
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          text: recent.modelData.right === recent.modelData.of ? G.trophy : T.category(recent.modelData.category).glyph
          size: 16
          color: recent.modelData.right === recent.modelData.of ? root.app.ui.yellow : root.app.tone(recent.modelData.category)
        }
        Column {
          anchors.left: recentGlyph.right
          anchors.leftMargin: 8
          anchors.right: score.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: T.category(recent.modelData.category).name
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: T.difficultyLabel(recent.modelData.difficulty) + (recent.modelData.at ? " · " + Qt.formatDate(new Date(recent.modelData.at), "d MMM") : "")
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
        }
        Text {
          id: score
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: recent.modelData.right + " / " + recent.modelData.of
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.weight: Font.Bold
          font.features: ({ "tnum": 1 })
        }
      }
    }
  }
}
