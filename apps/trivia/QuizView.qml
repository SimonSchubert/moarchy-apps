import QtQuick
import "kit"
import "Trivia.js" as T
import "Glyphs.js" as G

// A question, its answers, and after the pick what was right. The button
// that moves on sits at the foot of the screen, where a thumb already is, and
// is not there until there is something to move on from.
Item {
  id: root
  property var app
  readonly property var round: app.round
  readonly property var question: round ? T.current(round) : null
  readonly property bool answered: !!round && T.answered(round)
  readonly property bool last: !!round && round.index === round.questions.length - 1
  readonly property bool gotIt: answered && T.isRight(round, round.index)
  readonly property real column: Math.min(width - app.ui.gutter * 2, 760)
  readonly property int streak: app.book.stats.streak

  component Next: Button {
    visible: root.answered
    width: root.column
    implicitHeight: 46
    app: root.app
    primary: true
    glyph: root.last ? G.trophy : G.next
    text: root.last ? "See the score" : "Next question"
    onClicked: root.app.next()
  }

  Flickable {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: foot.top
    contentHeight: body.implicitHeight + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      x: (root.width - root.column) / 2
      y: root.app.compact ? 14 : 28
      width: root.column
      spacing: root.app.compact ? 16 : 22

      Progress {
        app: root.app
        round: root.round
        width: parent.width
      }

      // Which question, how hard, and the run you are on.
      Item {
        width: parent.width
        height: 24
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.round ? "Question " + (root.round.index + 1) + " / " + root.round.questions.length : ""
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          font.weight: Font.Bold
          font.capitalization: Font.AllUppercase
          font.letterSpacing: root.app.ui.tracking
          font.features: ({ "tnum": 1 })
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Row {
            visible: root.streak >= 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Icon { app: root.app; text: G.streak; size: 14; color: root.app.ui.orange; anchors.verticalCenter: parent.verticalCenter }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.streak
              color: root.app.ui.orange
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
              font.weight: Font.Bold
            }
          }
          Badge {
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            text: root.question ? T.difficultyLabel(root.question.difficulty) : ""
            tint: root.question ? root.app.difficultyTone(root.question.difficulty) : "transparent"
          }
        }
      }

      // The category, when the round is of anything.
      Row {
        visible: !!root.question && root.round.category === T.ANY
        spacing: 6
        Icon {
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          text: root.question ? T.category(root.question.category).glyph : ""
          size: 14
          color: root.question ? root.app.tone(root.question.category) : root.app.ui.muted
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.question ? T.category(root.question.category).name : ""
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.question ? root.question.text : ""
        color: root.app.ui.text
        lineHeight: 1.15
        font.family: root.app.ui.font
        font.pixelSize: root.app.compact
          ? (text.length > 140 ? 17 : 19)
          : (text.length > 140 ? 21 : 24)
        font.weight: Font.Bold
      }

      Item { width: 1; height: root.app.compact ? 2 : 6 }

      // True or false side by side; four answers one above the other, where
      // a long one has the width to wrap in.
      Grid {
        id: answers
        width: parent.width
        readonly property bool pair: !!root.question && root.question.type === "boolean"
        columns: pair ? 2 : 1
        spacing: 8
        Repeater {
          model: root.question ? root.question.answers : []
          delegate: AnswerButton {
            required property var modelData
            required property int index
            width: answers.pair ? (answers.width - 8) / 2 : answers.width
            app: root.app
            letter: "ABCD".charAt(index)
            text: modelData
            mark: !root.answered ? "open"
              : index === root.question.correct ? "right"
              : index === root.round.picks[root.round.index] ? "wrong" : "other"
            onClicked: root.app.choose(index)
          }
        }
      }

      // What the pick was.
      Row {
        visible: root.answered
        spacing: 8
        Icon {
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          text: root.gotIt ? G.right : G.wrong
          size: 16
          color: root.gotIt ? root.app.ui.good : root.app.ui.bad
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: root.column - 32
          wrapMode: Text.Wrap
          text: root.gotIt ? (root.streak >= 3 ? "Right — " + root.streak + " in a row." : "Right.")
            : "Not this time."
          color: root.gotIt ? root.app.ui.good : root.app.ui.bad
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.weight: Font.Bold
        }
      }

      // On a desktop the way on is under the answers, not a window away.
      Next { visible: !root.app.compact && root.answered }
      Text {
        visible: !root.app.compact && !root.answered
        text: "Click an answer, or press 1 – " + (root.question ? root.question.answers.length : 4)
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
    }
  }

  // The foot on a phone: moving on, where the thumb is.
  Item {
    id: foot
    visible: root.app.compact
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: visible ? 76 : 0

    Rectangle {
      width: parent.width
      height: 1
      color: root.app.ui.line
    }
    Next { anchors.centerIn: parent }
    Text {
      visible: !root.answered
      anchors.centerIn: parent
      text: "Tap an answer"
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
    }
  }
}
