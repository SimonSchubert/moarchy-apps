import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Reversi.js" as R

// The score, what the board is saying, and the two buttons: over the board on
// a phone, beside it on a desktop.
Column {
  id: controls
  property var app

  spacing: 14
  ScoreStrip {
    app: controls.app
    width: parent.width
    counts: controls.app.counts
    names: controls.app.names
    turn: controls.app.over ? -1 : controls.app.position.turn
  }
  Text {
    width: parent.width
    horizontalAlignment: controls.app.compact ? Text.AlignHCenter : Text.AlignLeft
    elide: Text.ElideRight
    text: controls.app.status
    color: controls.app.over ? controls.app.ui.accent : controls.app.ui.text
    font.family: controls.app.ui.font
    font.pixelSize: controls.app.ui.fs.lg
    font.weight: Font.DemiBold
  }
  // Undo stops at the end of a game: the result has gone into the record by
  // then, and a board that can be rewound past a recorded result can record a
  // second one. New game is the suggested tap once there is nothing to play.
  Row {
    x: controls.app.compact ? (parent.width - width) / 2 : 0
    spacing: 10
    Button {
      app: controls.app
      text: "Undo"
      glyph: KG.undo
      enabled: controls.app.canUndo
      onClicked: controls.app.undo()
    }
    Button {
      app: controls.app
      text: "New game"
      glyph: KG.refresh
      primary: controls.app.over
      onClicked: controls.app.askNewGame()
    }
  }
}
