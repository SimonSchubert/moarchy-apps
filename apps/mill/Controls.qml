import QtQuick
import "kit"
import "kit/Glyphs.js" as KG

// The score, what the board is saying, and the two buttons: beside the board
// on a desktop.
Column {
  id: controls
  property var app

  spacing: 14
  ScoreStrip {
    app: controls.app
    width: parent.width
    position: controls.app.position
    names: controls.app.names
    turn: controls.app.over ? -1 : controls.app.position.turn
  }
  Text {
    width: parent.width
    wrapMode: Text.Wrap
    text: controls.app.status
    color: controls.app.over ? controls.app.ui.accent : controls.app.ui.text
    font.family: controls.app.ui.font
    font.pixelSize: controls.app.ui.fs.lg
    font.weight: Font.Bold
  }
  // Undo stops at the end of a game: the result is in the record by then.
  // New game is the suggested tap once there is nothing left to play.
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
