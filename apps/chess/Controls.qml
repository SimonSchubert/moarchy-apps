import QtQuick
import "kit"
import "kit/Glyphs.js" as KG

// The players, what the board is saying, and the two buttons: beside the
// board on a desktop.
Column {
  id: controls
  property var app

  spacing: 14
  ScoreStrip {
    app: controls.app
    width: parent.width
    names: controls.app.names
    taken: controls.app.taken
    balance: controls.app.balance
    turn: controls.app.over ? -1 : controls.app.position.turn
  }
  Text {
    width: parent.width
    wrapMode: Text.Wrap
    text: controls.app.status
    color: controls.app.over ? controls.app.ui.accent
      : controls.app.checked ? controls.app.ui.bad : controls.app.ui.text
    font.family: controls.app.ui.font
    font.pixelSize: controls.app.ui.fs.lg
    font.weight: Font.Bold
  }
  // Undo stops at the end of a game: the result has gone into the record by
  // then, and a board that can be rewound past a recorded result can record
  // a second one. New game is the suggested tap once there is nothing to play.
  Row {
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
