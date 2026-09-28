import QtQuick
import "kit"
import "Trivia.js" as T
import "Store.js" as S
import "Glyphs.js" as G

// The score, and every question again with what you said and what was right.
// A phone stacks them, with Play again above the answers where the thumb is;
// a desktop puts the score beside the answers.
Item {
  id: root
  property var app
  readonly property var round: app.round
  readonly property int score: round ? T.score(round) : 0
  readonly property int of: round ? round.questions.length : 0
  readonly property var run: round ? T.runs(round) : ({ now: 0, best: 0 })
  readonly property var categoryBest: round && round.category !== T.ANY ? S.categoryRecord(app.book, round.category) : null

  component Label: Text {
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
    font.weight: Font.Bold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: root.app.ui.tracking
  }

  // The score and what to do next.
  component Summary: Column {
    id: summary
    spacing: 16

    Label { text: "Round over" }
    Row {
      spacing: 10
      Text {
        id: bigScore
        text: root.score
        color: root.score * 2 >= root.of ? root.app.ui.good : root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.compact ? 60 : 72
        font.weight: Font.Bold
        font.features: ({ "tnum": 1 })
      }
      Text {
        anchors.baseline: bigScore.baseline
        text: "/ " + root.of
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.compact ? 26 : 30
        font.features: ({ "tnum": 1 })
      }
    }
    Column {
      width: parent.width
      spacing: 4
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: T.verdict(root.score, root.of)
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xl
        font.weight: Font.Bold
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.round ? T.category(root.round.category).name + " · " + T.difficultyLabel(root.round.difficulty) : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
    }
    Progress {
      app: root.app
      round: root.round
      width: parent.width
      size: 10
    }

    // Three figures: this round's share, its longest run, and the best you
    // have done at the category -- or your run across rounds, for Anything.
    Row {
      width: parent.width
      spacing: 8
      Repeater {
        model: [
          [T.percent(root.score, root.of) + "%", "Right"],
          [String(root.run.best), "Best run"],
          root.categoryBest ? [root.categoryBest.best + "%", "Category best"] : [String(root.app.book.stats.bestStreak), "Longest ever"]
        ]
        delegate: Rectangle {
          required property var modelData
          width: (summary.width - 16) / 3
          height: 66
          radius: root.app.ui.radius
          color: root.app.ui.surface
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
              font.pixelSize: root.app.ui.fs.lg + 3
              font.weight: Font.Bold
              font.features: ({ "tnum": 1 })
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: modelData[1]
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: 10
              font.capitalization: Font.AllUppercase
              font.letterSpacing: 0.8
            }
          }
        }
      }
    }

    Button {
      width: parent.width
      implicitHeight: 46
      app: root.app
      primary: true
      glyph: G.next
      text: "Play again"
      onClicked: root.app.again()
    }
    Button {
      width: parent.width
      app: root.app
      text: "Categories"
      onClicked: root.app.home()
    }
  }

  // Every question, with the answer given and the one that was right.
  component Review: Column {
    spacing: 8
    Label { text: "The answers" }
    Repeater {
      model: root.round ? root.round.questions : []
      delegate: Rectangle {
        id: item
        required property var modelData
        required property int index
        readonly property bool good: T.isRight(root.round, index)
        readonly property int picked: index < root.round.picks.length ? root.round.picks[index] : -1
        width: parent.width
        height: lines.implicitHeight + 24
        radius: root.app.ui.radius
        color: root.app.ui.surface
        border.width: 1
        border.color: root.app.ui.line

        Rectangle {
          x: 12
          y: 12
          width: 24
          height: 24
          radius: root.app.ui.radius
          color: root.app.ui.alpha(item.good ? root.app.ui.good : root.app.ui.bad, 0.16)
          Icon {
            anchors.centerIn: parent
            app: root.app
            text: item.good ? G.right : G.wrong
            size: 14
            color: item.good ? root.app.ui.good : root.app.ui.bad
          }
        }
        Column {
          id: lines
          x: 48
          y: 12
          width: parent.width - 60
          spacing: 6
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: (item.index + 1) + ". " + item.modelData.text
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
          }
          Text {
            visible: !item.good && item.picked >= 0
            width: parent.width
            wrapMode: Text.Wrap
            text: "You said " + (item.picked >= 0 ? item.modelData.answers[item.picked] : "")
            color: root.app.ui.bad
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            font.strikeout: true
          }
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: item.modelData.answers[item.modelData.correct]
            color: root.app.ui.good
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            font.weight: Font.Bold
          }
        }
      }
    }
  }

  // Phone: one column.
  Flickable {
    anchors.fill: parent
    visible: root.app.compact
    contentHeight: phoneCol.implicitHeight + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: phoneCol
      x: root.app.ui.gutter
      y: 16
      width: root.width - root.app.ui.gutter * 2
      spacing: 28
      Summary { width: parent.width }
      Review { width: parent.width }
    }
  }

  // Desktop: the score beside the answers.
  Item {
    anchors.fill: parent
    visible: !root.app.compact
    Flickable {
      id: left
      x: root.app.ui.gutter + 8
      y: 0
      width: Math.min(360, root.width * 0.38)
      height: parent.height
      contentHeight: deskSummary.implicitHeight + 56
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Summary { id: deskSummary; y: 28; width: parent.width }
    }
    Flickable {
      anchors.left: left.right
      anchors.leftMargin: 36
      anchors.right: parent.right
      anchors.rightMargin: root.app.ui.gutter
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      contentHeight: deskReview.implicitHeight + 56
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Review { id: deskReview; y: 28; width: Math.min(parent.width, 720) }
    }
  }
}
