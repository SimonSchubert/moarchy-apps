import QtQuick

// Several lines of text in a box that scrolls: a note, a message, a file.
// Focus comes from a press, as with TextField; Escape hands the keys back to
// the window. `plain` drops the box, for an editor that is the whole page.
Rectangle {
  id: root
  property var app
  property alias text: edit.text
  property alias edit: edit
  property string placeholder: ""
  property bool plain: false
  property alias readOnly: edit.readOnly
  property int pixelSize: app.ui.fs.md
  property string family: app.ui.font

  implicitHeight: 160
  radius: plain ? 0 : app.ui.radius
  color: plain ? "transparent" : app.ui.bg
  border.width: plain ? 0 : (edit.activeFocus ? 2 : 1)
  border.color: edit.activeFocus ? app.ui.accent : app.ui.border

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.margins: root.plain ? 0 : 10
    contentWidth: width
    contentHeight: edit.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // Keep the caret in view while typing.
    function ensureVisible(r) {
      if (contentY >= r.y) contentY = r.y
      else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
    }

    TextEdit {
      id: edit
      width: flick.width
      wrapMode: TextEdit.Wrap
      color: root.app.ui.text
      selectionColor: root.app.ui.accent
      selectedTextColor: root.app.ui.inkOnAccent
      font.family: root.family
      font.pixelSize: root.pixelSize
      activeFocusOnPress: true
      onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
      Keys.onEscapePressed: function (event) { root.app.resetFocus(); event.accepted = true }

      Text {
        anchors.fill: parent
        visible: !edit.text && !edit.activeFocus
        text: root.placeholder
        color: root.app.ui.muted
        font: edit.font
        wrapMode: Text.Wrap
      }
    }
  }
}
