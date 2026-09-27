import QtQuick
import "Game.js" as G

// Thirty tiles. A submitted row flips, a tile at a time left to right -- the
// reveal is the whole theatre of this game -- and a refused one shakes.
//
// A tile carries a mark as well as a colour: a filled dot in the corner of a
// letter that is in the right place, an open ring for one that is in the word
// somewhere else, and nothing for one that is not. The colours are the rules,
// but one mark a tile is the difference between a playable board and an
// unplayable one for about one man in twelve. The bottom-right corner, because
// these are capitals: nothing descends, so a mark there is never on a letter.
Item {
  id: root
  property var app
  property var game: null
  property string typed: ""
  // The row being revealed or refused, and how far through it is (ms).
  property int flipRow: -1
  property int shakeRow: -1
  property real t: 0
  readonly property bool busy: flipRow >= 0 || shakeRow >= 0
  signal settled()

  readonly property real flipMs: 280
  readonly property real staggerMs: 110
  readonly property real shakeMs: 380
  readonly property real gap: 6
  readonly property real maxTile: app.compact ? 58 : 76
  readonly property real tile: Math.max(20, Math.min(maxTile,
    (width - gap * (G.LENGTH - 1)) / G.LENGTH, (height - gap * (G.GUESSES - 1)) / G.GUESSES))

  function reveal(row) {
    shakeRow = -1
    flipRow = row
    clock.duration = flipMs + staggerMs * (G.LENGTH - 1)
    clock.restart()
  }
  function refuse(row) {
    flipRow = -1
    shakeRow = row
    clock.duration = shakeMs
    clock.restart()
  }

  NumberAnimation {
    id: clock
    target: root
    property: "t"
    from: 0
    to: duration
    onFinished: {
      root.flipRow = -1
      root.shakeRow = -1
      root.settled()
    }
  }

  readonly property real shake: shakeRow < 0 ? 0
    : Math.sin(Math.min(t / shakeMs, 1) * Math.PI * 5) * 7 * (1 - Math.min(t / shakeMs, 1))

  Column {
    anchors.centerIn: parent
    spacing: root.gap

    Repeater {
      model: G.GUESSES
      delegate: Row {
        id: line
        required property int index
        spacing: root.gap
        x: root.shakeRow === index ? root.shake : 0

        Repeater {
          model: G.LENGTH
          delegate: Item {
            id: cell
            required property int index
            readonly property int row: line.index
            width: root.tile
            height: root.tile

            readonly property var guess: root.game && row < root.game.guesses.length ? root.game.guesses[row] : null
            readonly property string letter: guess ? guess.word[index]
              : root.game && row === root.game.guesses.length && index < root.typed.length ? root.typed[index] : ""
            // How far through its turn this tile is: < 0.5 still face down,
            // edge on at 0.5, where it changes sides.
            readonly property real share: root.flipRow === row ? (root.t - root.staggerMs * index) / root.flipMs : 1
            readonly property bool filled: guess !== null && share >= 0.5
            readonly property int mark: guess ? guess.marks[index] : G.ABSENT
            readonly property real squash: share <= 0 || share >= 1 ? 1 : Math.max(Math.abs(Math.cos(Math.PI * share)), 0.04)
            readonly property color fill: mark === G.CORRECT ? root.app.ui.correct
              : mark === G.PRESENT ? root.app.ui.present : root.app.ui.absent
            readonly property color ink: !filled ? root.app.ui.text
              : mark === G.CORRECT ? root.app.ui.inkOnCorrect
              : mark === G.PRESENT ? root.app.ui.inkOnPresent : root.app.ui.inkOnAbsent

            Accessible.role: Accessible.StaticText
            Accessible.name: letter === "" ? "Empty" : letter + (filled ? (mark === G.CORRECT ? ", in place" : mark === G.PRESENT ? ", elsewhere" : ", not in the word") : "")

            Item {
              anchors.fill: parent
              transform: Scale { origin.y: cell.height / 2; yScale: cell.squash }

              Rectangle {
                anchors.fill: parent
                radius: root.tile * 0.14
                color: cell.filled ? cell.fill : "transparent"
                border.width: cell.filled ? 0 : 2
                border.color: cell.letter !== "" ? root.app.ui.typedEdge : root.app.ui.edge
              }
              Text {
                anchors.centerIn: parent
                text: cell.letter
                color: cell.ink
                font.family: root.app.ui.font
                font.pixelSize: Math.round(root.tile * 0.52)
                font.weight: Font.Bold
              }
              // The shape that says which colour this is without being it.
              Rectangle {
                visible: cell.filled && cell.mark !== G.ABSENT
                readonly property real spot: root.tile * 0.115
                width: spot * 2
                height: width
                radius: spot
                x: root.tile - spot * 1.7 - spot
                y: root.tile - spot * 1.7 - spot
                color: cell.mark === G.CORRECT ? cell.ink : "transparent"
                border.width: cell.mark === G.CORRECT ? 0 : Math.max(root.tile * 0.035, 1.5)
                border.color: cell.ink
                scale: cell.mark === G.CORRECT ? 1 : 0.82
              }
            }
          }
        }
      }
    }
  }
}
