import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Pegs.js" as P
import "Store.js" as S

// The nine figures, each a puzzle and how it has gone. A list rather than a
// drop-down, because here the choice is the content: nine different puzzles,
// each with a shape and a record behind it, and a drop-down would hide eight
// of them behind a word. Tapping one starts it; there is nothing else to fill
// in, so there is no Start button.
Column {
  id: root
  property var app
  property var game: S.fresh()
  // The figure on the board now, marked.
  property string current: ""
  signal chosen(string key)

  spacing: 4

  Text {
    width: parent.width
    wrapMode: Text.Wrap
    text: "Every one of these can be reduced to a single peg. The app solves them all before it ships."
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.sm
    bottomPadding: 6
  }

  Repeater {
    model: P.FIGURES
    delegate: ListRow {
      id: row
      required property var modelData
      required property int index
      readonly property var entry: S.recordFor(root.game, modelData.key)
      app: root.app
      width: root.width
      title: (root.app.compact ? "" : (index + 1) + "  ") + modelData.label
      text: modelData.blurb
      glyph: modelData.key === root.current ? KG.check : ""
      glyphColor: root.app.ui.accent
      selected: modelData.key === root.current && !root.app.compact
      // The fewest pegs this figure has been left at, in three characters or
      // fewer: a star for one peg in the middle, where that is the goal.
      trailing: !entry.best ? "—"
        : entry.best === 1 && entry.perfect && modelData.centre ? "★"
        : String(entry.best)
      trailingColor: entry.best === 1 ? root.app.ui.pick : root.app.ui.muted
      onClicked: root.chosen(modelData.key)
    }
  }
}
