import QtQuick
import "Klondike.js" as K

// One card, face up or face down.
//
// What is visible of a covered card is a strip at its top, so the index --
// rank and pip -- lives there and nowhere else. The card nothing covers gets
// the big pip in the middle as well: it is the one card in the pile a tap can
// pick up, and a big symbol says which card that is faster than a small one.
Rectangle {
  id: root
  property var app
  property int card: 0
  property bool faceUp: true
  // Nothing on top of it.
  property bool full: true

  // A card keeps a sliver of a corner even on a square screen: without one it
  // reads as a tile, not a card. The full curve comes back with a rounded
  // theme.
  radius: app.ui.radius > 0 ? width * 0.12 : 2
  color: faceUp ? app.ui.cardFace : app.ui.cardBack
  border.width: 1
  border.color: faceUp ? app.ui.cardEdge : app.ui.cardBackLine
  antialiasing: true

  readonly property color ink: K.isRed(card) ? app.ui.cardRed : app.ui.cardInk

  // The back: a lattice rather than a picture. It is the one thing that makes
  // a stack of backs read as a stack rather than a coloured rectangle.
  Item {
    visible: !root.faceUp
    anchors.fill: parent
    anchors.margins: 3
    clip: true
    Repeater {
      model: 7
      delegate: Rectangle {
        required property int index
        width: 1
        height: root.height * 2
        x: -root.height * 0.6 + index * root.width * 0.3
        y: -root.height * 0.5
        rotation: -34
        color: root.app.ui.cardBackLine
      }
    }
  }

  Text {
    visible: root.faceUp
    x: root.width * 0.09
    y: root.height * 0.02
    text: K.RANK_NAMES[K.rank(root.card)]
    color: root.ink
    font.family: root.app.ui.font
    font.pixelSize: Math.max(8, root.height * 0.27)
    font.weight: Font.Bold
    // "10" is the widest index there is.
    font.letterSpacing: K.rank(root.card) === 9 ? -root.height * 0.02 : 0
  }
  Pip {
    visible: root.faceUp
    suit: K.suit(root.card)
    size: root.height * 0.085
    color: root.ink
    x: root.width * 0.74 - size
    y: root.height * 0.145 - size
  }
  Pip {
    visible: root.faceUp && root.full
    suit: K.suit(root.card)
    size: root.height * 0.20
    color: root.ink
    x: root.width * 0.5 - size
    y: root.height * 0.66 - size
  }
}
