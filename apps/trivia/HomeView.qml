import QtQuick
import "kit"
import "Trivia.js" as T
import "Store.js" as S
import "Glyphs.js" as G

// Where a round starts: the one you were in, if there is one; the next round
// on the last pick, one tap away; how hard, how many and what kind; and the
// categories, each of which is a round the moment it is tapped.
Flickable {
  id: root
  property var app
  readonly property var book: app.book
  readonly property var pick: app.pick
  readonly property int gap: 8
  readonly property real inner: width - app.ui.gutter * 2
  readonly property int columns: app.compact ? 2 : Math.max(2, Math.floor((inner + gap) / (176 + gap)))

  contentHeight: body.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  component Label: Text {
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
    font.weight: Font.Bold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: root.app.ui.tracking
  }

  Column {
    id: body
    x: root.app.ui.gutter
    y: root.app.compact ? 14 : root.app.ui.gutter
    width: root.inner
    spacing: 18

    // The round left for the categories, offered back.
    Card {
      visible: root.app.resumable
      app: root.app
      width: parent.width
      clickable: true
      title: "Unfinished round"
      glyph: G.question
      glyphColor: root.app.ui.accent
      trailing: root.app.round ? (root.app.round.index + 1) + " / " + root.app.round.questions.length : ""
      onClicked: root.app.resume()
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: root.app.round ? T.category(root.app.round.category).name + " · " + T.score(root.app.round) + " right so far" : ""
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
      }
    }

    // The next round, on the last pick.
    Rectangle {
      width: parent.width
      height: hero.implicitHeight + 36
      radius: root.app.ui.radius
      color: root.app.ui.surface
      border.width: 1
      border.color: root.app.ui.line

      Rectangle {
        width: 3
        height: parent.height
        radius: root.app.ui.radius
        color: root.app.tone(root.pick.category)
      }

      Column {
        id: hero
        x: 20
        y: 18
        width: parent.width - 40
        spacing: 12

        Label { text: "Next round" }
        Row {
          spacing: 12
          width: parent.width
          Rectangle {
            id: heroMark
            width: 48
            height: 48
            radius: root.app.ui.radius
            color: root.app.ui.alpha(root.app.tone(root.pick.category), 0.16)
            Icon {
              anchors.centerIn: parent
              app: root.app
              text: T.category(root.pick.category).glyph
              size: 26
              color: root.app.tone(root.pick.category)
            }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - heroMark.width - 12 - (playWide.visible ? playWide.width + 12 : 0)
            spacing: 4
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: T.category(root.pick.category).name
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xl
              font.weight: Font.Bold
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: root.pick.amount + " questions · " + T.difficultyLabel(root.pick.difficulty) + " · " + T.typeLabel(root.pick.type)
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
          }
          Button {
            id: playWide
            visible: !root.app.compact
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            primary: true
            glyph: G.next
            text: "Play"
            implicitHeight: 42
            implicitWidth: 132
            onClicked: root.app.play()
          }
        }
        Button {
          visible: root.app.compact
          width: parent.width
          implicitHeight: 46
          app: root.app
          primary: true
          glyph: G.next
          text: "Play"
          onClicked: root.app.play()
        }
      }
    }

    // How hard, how many, what kind.
    Grid {
      width: parent.width
      // Side by side where they fit on a line each, and the kinds get the
      // most room: their words are longest. Stacked where they do not.
      readonly property bool stacked: root.app.compact || width < 740
      columns: stacked ? 1 : 3
      columnSpacing: 24
      rowSpacing: 14
      function cell(share) { return stacked ? width : (width - 48) * share }

      Column {
        width: parent.cell(0.32)
        spacing: 8
        Label { text: "Difficulty" }
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: T.DIFFICULTIES
            delegate: Chip {
              required property var modelData
              app: root.app
              hpad: root.app.compact ? 16 : 12
              text: modelData.label
              selected: root.pick.difficulty === modelData.key
              onClicked: root.app.setPick({ difficulty: modelData.key })
            }
          }
        }
      }
      Column {
        width: parent.cell(0.25)
        spacing: 8
        Label { text: "Questions" }
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: T.LENGTHS
            delegate: Chip {
              required property var modelData
              app: root.app
              hpad: root.app.compact ? 16 : 12
              text: String(modelData)
              selected: root.pick.amount === modelData
              onClicked: root.app.setPick({ amount: modelData })
            }
          }
        }
      }
      Column {
        width: parent.cell(0.43)
        spacing: 8
        Label { text: "Kind" }
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: T.TYPES
            delegate: Chip {
              required property var modelData
              app: root.app
              hpad: root.app.compact ? 16 : 12
              text: modelData.label
              selected: root.pick.type === modelData.key
              onClicked: root.app.setPick({ type: modelData.key })
            }
          }
        }
      }
    }

    // The categories: a tap is a round.
    Column {
      width: parent.width
      spacing: 10
      Item {
        width: parent.width
        height: 16
        Label { text: "Categories" }
        Text {
          anchors.right: parent.right
          text: "Tap one to play"
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
        }
      }
      Grid {
        width: parent.width
        columns: root.columns
        spacing: root.gap
        Repeater {
          model: T.CATEGORIES
          delegate: CategoryTile {
            required property var modelData
            width: (root.inner - root.gap * (root.columns - 1)) / root.columns
            app: root.app
            category: modelData
            current: root.pick.category === modelData.id
            tally: modelData.id === T.ANY
              ? { answered: root.book.stats.answered, right: root.book.stats.right }
              : S.categoryRecord(root.book, modelData.id)
            onClicked: root.app.play(modelData.id)
          }
        }
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.Wrap
      text: "Questions from the Open Trivia Database, opentdb.com, under CC BY-SA 4.0."
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
    }
  }
}
