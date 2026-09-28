import QtQuick
import "kit"

// A short list of things to do to one message, a draft or a link: a sheet from
// the bottom on a phone, a card in the middle on a desktop. It is the app's
// open dialog while it is up, so Back and Escape close it before anything
// else, as they do a kit Dialog.
//
//   sheet.show("Subject", [{ text: "Archive", glyph: G.archive, run: fn }, ...])
//
// An action with `destructive: true` is drawn in the theme's red.
Item {
  id: root
  property var app
  property string title: ""
  // Under the title: where a link goes, who a message is from.
  property string detail: ""
  property var actions: []

  readonly property bool shown: app && app.dialog === root

  parent: app ? app.overlay : null
  anchors.fill: parent
  visible: shown
  z: 10

  function show(title, actions, detail) {
    root.title = title || ""
    root.detail = detail || ""
    root.actions = (actions || []).filter(function (a) { return a && a.visible !== false })
    app.resetFocus()
    app.dialog = root
  }
  function close() { if (app.dialog === root) app.dialog = null }
  // Enter, with the sheet up: the first action.
  function accept() { if (actions.length) run(actions[0]) }
  function run(action) {
    close()
    if (typeof action.run === "function") action.run()
  }

  Rectangle {
    anchors.fill: parent
    color: root.app ? root.app.ui.scrim : "transparent"
    MouseArea { anchors.fill: parent; onClicked: root.close() }
  }

  Rectangle {
    id: sheet
    readonly property bool atBottom: root.app.compact
    width: atBottom ? parent.width : Math.min(400, parent.width - 48)
    height: col.implicitHeight + 24 + (atBottom ? root.app.bottomInset : 0)
    anchors.horizontalCenter: parent.horizontalCenter
    y: atBottom ? parent.height - height : (parent.height - height) / 2
    radius: root.app.ui.radius
    color: root.app.ui.bg
    border.width: 1
    border.color: root.app.ui.line
    MouseArea { anchors.fill: parent }

    Column {
      id: col
      x: 12
      y: 12
      width: parent.width - 24
      spacing: 2

      Text {
        visible: root.title !== ""
        x: 10
        width: parent.width - 20
        topPadding: 6
        bottomPadding: root.detail !== "" ? 0 : 8
        text: root.title
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
        font.weight: Font.Bold
        elide: Text.ElideRight
      }
      Text {
        visible: root.detail !== ""
        x: 10
        width: parent.width - 20
        bottomPadding: 8
        text: root.detail
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 4
        elide: Text.ElideRight
      }

      Repeater {
        model: root.actions
        delegate: ListRow {
          id: row
          required property var modelData
          width: col.width
          app: root.app
          glyph: row.modelData.glyph || ""
          glyphColor: row.modelData.destructive ? root.app.ui.bad : root.app.ui.muted
          title: row.modelData.text
          onClicked: root.run(row.modelData)
        }
      }
    }
  }
}
