import QtQuick
import "kit"
import "Glyphs.js" as G
import "Facts.js" as F

// The packets already pointed at, newest first, each with its Nutri-Score as
// a small letter on the right. A tap opens the cached product, so a shop with
// no signal still has yesterday's scan.
Item {
  id: root
  property var app
  property var items: []
  property string selected: ""
  property int current: -1
  property alias query: search.text
  signal opened(string code)

  function focusField() { search.input.forceActiveFocus() }
  function show(index) { if (index >= 0) list.positionViewAtIndex(index, ListView.Contain) }

  SearchField {
    id: search
    visible: root.items.length > 0 || root.query !== ""
    app: root.app
    x: root.app.ui.gutter
    y: 4
    width: parent.width - root.app.ui.gutter * 2
    placeholder: "Name, brand or barcode"
    onEscaped: root.app.resetFocus()
  }

  Keyed { id: keyed; items: root.items.map(function (p) { return Object.assign({ key: p.code }, p) }) }

  ListView {
    id: list
    anchors.top: search.visible ? search.bottom : parent.top
    anchors.topMargin: 8
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.app.compact ? 4 : root.app.ui.gutter - 8
    anchors.rightMargin: anchors.leftMargin
    clip: true
    spacing: 2
    boundsBehavior: Flickable.StopAtBounds
    model: keyed
    delegate: ListRow {
      id: row
      required property string key
      required property int index
      readonly property var p: keyed.at(key)
      width: list.width
      app: root.app
      title: p.name || ""
      text: p.code ? (F.subtitle(p) || p.code) : ""
      selected: key === root.selected || index === root.current
      onClicked: root.opened(key)
      Rectangle {
        width: 30
        height: 30
        radius: root.app.ui.radius
        color: row.p.nutriscore ? root.app.ui.gradeFill(row.p.nutriscore) : root.app.ui.surfaceHigh
        border.width: 1
        border.color: row.p.nutriscore ? root.app.ui.gradeHue(row.p.nutriscore) : root.app.ui.line
        Text {
          anchors.centerIn: parent
          text: row.p.nutriscore ? row.p.nutriscore.toUpperCase() : F.DASH
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.weight: Font.Bold
        }
      }
    }
    footer: Item { width: 1; height: 12 }
  }

  EmptyState {
    anchors.centerIn: parent
    visible: root.items.length === 0
    app: root.app
    glyph: root.query !== "" ? G.missing : G.history
    title: root.query !== "" ? "No match" : "Nothing scanned yet"
    text: root.query !== "" ? "Nothing in the history is called “" + root.query + "”."
      : "Point the camera at a barcode. That is the only way a product gets here."
  }
}
