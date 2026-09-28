import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G

// The result when there is one, how many pegs are left, what there is to do,
// and the buttons: over and under the board on a phone, beside it on a
// desktop.
Column {
  id: root
  property var app
  // The buttons are in the phone's bottom bar, not here.
  property bool buttons: true
  spacing: 12

  // The result, with the one thing to do about it. A banner rather than a
  // toast: a stuck board is a state the screen is in, not an event.
  Rectangle {
    visible: root.app.over
    width: parent.width
    height: bannerCol.implicitHeight + 24
    radius: root.app.ui.radius
    color: root.app.ui.accentSoft
    border.width: 1
    border.color: root.app.ui.accent
    Column {
      id: bannerCol
      x: 14
      y: 12
      width: parent.width - 28
      spacing: 10
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.app.resultText
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
        font.weight: Font.Bold
      }
      Button {
        app: root.app
        primary: true
        glyph: KG.refresh
        text: "Start again"
        onClicked: root.app.startAgain()
      }
    }
  }

  Text {
    width: parent.width
    horizontalAlignment: root.app.compact ? Text.AlignHCenter : Text.AlignLeft
    text: root.app.pegsLeft === 1 ? "1 peg" : root.app.pegsLeft + " pegs"
    color: root.app.ui.text
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xl
    font.weight: Font.Bold
    font.features: ({ "tnum": 1 })
  }

  Text {
    visible: !root.app.compact
    width: parent.width
    wrapMode: Text.Wrap
    text: root.app.status
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
  }

  Row {
    visible: root.buttons
    spacing: 10
    Button {
      app: root.app
      glyph: KG.undo
      text: "Undo"
      enabled: root.app.canUndo
      onClicked: root.app.undo()
    }
    Button {
      app: root.app
      glyph: G.hint
      text: root.app.thinking ? "Looking…" : "Hint"
      enabled: root.app.canHint
      onClicked: root.app.hint()
    }
    Button {
      visible: !root.app.over
      app: root.app
      glyph: KG.refresh
      text: "Start again"
      enabled: root.app.game.moves.length > 0
      onClicked: root.app.startAgain()
    }
  }
}
