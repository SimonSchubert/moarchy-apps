import QtQuick

// A scrolling page of cards in columns. `layout` is the columns, each a list
// of names from `cards`; a page picks a layout per column count, so the
// columns come out about the same height at every width rather than one tall
// and one short.
Flickable {
  id: root
  property var app
  property var layout: []
  property var cards: ({})

  contentWidth: width
  contentHeight: grid.implicitHeight + (app.compact ? 4 : 8) + app.ui.gutter
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  function toTop() { contentY = 0 }

  Row {
    id: grid
    x: root.app.ui.gutter
    y: root.app.compact ? 4 : 8
    width: root.width - root.app.ui.gutter * 2
    spacing: root.app.ui.gutter

    Repeater {
      model: root.layout
      delegate: Column {
        id: column
        required property var modelData
        width: (grid.width - (root.layout.length - 1) * grid.spacing) / Math.max(1, root.layout.length)
        spacing: root.app.ui.gutter
        Repeater {
          model: column.modelData
          delegate: Loader {
            required property var modelData
            width: column.width
            sourceComponent: root.cards[modelData] || null
          }
        }
      }
    }
  }
}
