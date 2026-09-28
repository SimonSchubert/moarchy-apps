import QtQuick
import "kit"
import "kit/Glyphs.js" as KG

// The score, the status and the two buttons: over the board on a phone,
// beside it on a desktop.
Column {
  id: controls
  property var app

  spacing: 14
  ScoreStrip {
    app: controls.app
    width: parent.width
    names: controls.app.names
    marks: controls.app.marks
    series: controls.app.game.series
    turn: controls.app.over ? -1 : controls.app.position.turn
  }
  Text {
    width: parent.width
    horizontalAlignment: controls.app.compact ? Text.AlignHCenter : Text.AlignLeft
    text: controls.app.status
    color: controls.app.over ? controls.app.ui.accent : controls.app.ui.text
    font.family: controls.app.ui.font
    font.pixelSize: controls.app.ui.fs.lg
    font.weight: Font.Bold
  }
  // The two buttons trade places: exactly one of them is ever the obvious
  // tap, which on a board where a game lasts fifteen seconds is what stops
  // a thumb from throwing one away.
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
      text: "Play again"
      glyph: KG.refresh
      primary: controls.app.over
      enabled: controls.app.over
      onClicked: controls.app.rematch()
    }
  }
}
