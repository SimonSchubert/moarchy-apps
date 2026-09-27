import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Notes.js" as N
import "Glyphs.js" as G

// The open note. Not a form: no Save, no field boxes, no separators. The note
// fills its space in its own colour, the title is bigger than the body, and
// everything typed is already saved -- half a second after the last key, and
// again when it closes.
//
// The fields are the truth while it is open: typing writes into `draft`, and
// the draft goes to the app on a timer. A ticked, added or removed item is a
// change of shape, and rebuilds the rows; a letter typed is not.
Rectangle {
  id: root
  property var app
  property string noteId: ""
  // Put the cursor in the note at once: it exists because somebody tapped
  // "Take a note".
  property bool fresh: false
  // A pane beside the grid, with a close button, rather than a page with a
  // way back.
  property bool pane: false

  property var draft: null
  property int shape: 0            // bumped on every change of shape
  property real stamp: 0
  property bool showDone: true
  property bool picking: false
  property int focusItem: -1
  // The draft's colour, as a property: a field written inside a JS object
  // tells no binding.
  property string colour: "default"

  color: app.noteFill(colour)

  Component.onCompleted: {
    var n = N.get(app.notes, noteId)
    draft = n ? N.clone(n) : null
    stamp = draft ? draft.edited : 0
    colour = draft ? draft.colour : "default"
    if (fresh) Qt.callLater(focusFirst)
  }
  Component.onDestruction: finish()

  function touched(touch) {
    if (!draft) return
    if (touch !== false) {
      draft.edited = N.now()
      stamp = draft.edited
    }
    commit.restart()
  }
  function reshaped() { shape += 1; touched() }

  Timer { id: commit; interval: 500; onTriggered: root.app.saveNote(root.draft) }

  function finish() {
    if (!draft) return
    commit.stop()
    app.finishNote(draft)
    draft = null
  }

  function focusFirst() {
    if (!draft) return
    if (draft.kind === N.LIST) { focusItem = 0; shape += 1 }
    else body.forceActiveFocus()
  }

  // Rows as { item, index } into draft.items: open ones, then ticked.
  function rows(done) {
    var s = shape
    if (!draft || draft.kind !== N.LIST) return []
    var out = []
    for (var i = 0; i < draft.items.length; i++)
      if (!!draft.items[i].done === done) out.push({ index: i })
    return out
  }

  function addItem(after) {
    var at = after < 0 ? draft.items.length : after + 1
    draft.items.splice(at, 0, { text: "", done: false })
    focusItem = at
    reshaped()
  }
  function removeItem(i, focusPrevious) {
    draft.items.splice(i, 1)
    if (!draft.items.length) draft.items.push({ text: "", done: false })
    focusItem = focusPrevious ? Math.max(0, i - 1) : -1
    reshaped()
  }
  function tick(i) {
    draft.items[i].done = !draft.items[i].done
    focusItem = -1
    app.resetFocus()
    reshaped()
  }
  function convert() {
    app.resetFocus()
    draft = draft.kind === N.LIST ? N.toText(draft) : N.toList(draft)
    if (draft.kind === N.LIST && !draft.items.length) draft.items.push({ text: "", done: false })
    reshaped()
  }
  function recolour(key) {
    draft.colour = key
    colour = key
    touched(false)
  }
  function togglePin() {
    draft.pinned = !draft.pinned
    pinButton.active = draft.pinned
    touched(false)
  }

  // ------------------------------------------------------------ the top

  Item {
    id: head
    width: parent.width
    height: root.app.compact ? 56 : 60

    IconButton {
      x: 4
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      glyph: root.pane ? KG.close : KG.back
      label: root.pane ? "Close" : "Back"
      onClicked: root.app.back()
    }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      IconButton {
        id: pinButton
        app: root.app
        glyph: active ? G.pin : G.pinOutline
        label: active ? "Unpin" : "Pin"
        active: root.draft ? root.draft.pinned : false
        onClicked: root.togglePin()
      }
      IconButton {
        app: root.app
        glyph: G.palette
        label: "Colour"
        active: root.picking
        onClicked: root.picking = !root.picking
      }
      IconButton {
        app: root.app
        glyph: root.draft && root.draft.kind === N.LIST ? G.text : G.list
        label: root.draft && root.draft.kind === N.LIST ? "Hide tick boxes" : "Tick boxes"
        onClicked: root.convert()
      }
      IconButton {
        app: root.app
        glyph: KG.remove
        label: "Delete note"
        onClicked: root.app.deleteNote(root.noteId)
      }
    }
  }

  ColourGrid {
    id: colours
    visible: root.picking
    anchors.top: head.bottom
    x: 12
    width: parent.width - 24
    height: visible ? implicitHeight + 8 : 0
    app: root.app
    selected: root.colour
    onPicked: function (key) { root.recolour(key) }
  }

  // ------------------------------------------------------------ the note

  Flickable {
    id: flick
    anchors.top: colours.bottom
    anchors.bottom: foot.top
    anchors.left: parent.left
    anchors.right: parent.right
    contentWidth: width
    contentHeight: content.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: content
      x: 18
      y: 4
      width: Math.min(flick.width - 36, 700)
      spacing: 12

      TextEdit {
        id: title
        width: parent.width
        text: root.draft ? root.draft.title : ""
        wrapMode: TextEdit.Wrap
        color: root.app.ui.text
        selectionColor: root.app.ui.accent
        selectedTextColor: root.app.ui.inkOnAccent
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.lg + 4
        font.weight: Font.DemiBold
        inputMethodHints: Qt.ImhNoPredictiveText
        onTextChanged: if (root.draft && text !== root.draft.title) { root.draft.title = text; root.touched() }
        // Enter in the title goes to the note: a title is one line.
        Keys.onReturnPressed: root.focusFirst()
        Keys.onEnterPressed: root.focusFirst()
        Text {
          anchors.fill: parent
          visible: !title.text && !title.activeFocus
          text: "Title"
          color: root.app.ui.muted
          font: title.font
        }
      }

      TextEdit {
        id: body
        visible: root.draft !== null && root.draft.kind !== N.LIST
        width: parent.width
        // Tapping anywhere under a one-line note puts the cursor in it.
        height: Math.max(implicitHeight, flick.height - title.height - 40)
        text: root.draft && root.draft.kind !== N.LIST ? root.draft.body : ""
        wrapMode: TextEdit.Wrap
        color: root.app.ui.text
        selectionColor: root.app.ui.accent
        selectedTextColor: root.app.ui.inkOnAccent
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md + 1
        onTextChanged: if (root.draft && root.draft.kind !== N.LIST && text !== root.draft.body) { root.draft.body = text; root.touched() }
        Text {
          visible: !body.text && !body.activeFocus
          text: "Note"
          color: root.app.ui.muted
          font: body.font
        }
      }

      // --- a list

      Column {
        visible: root.draft !== null && root.draft.kind === N.LIST
        width: parent.width
        spacing: 2

        Repeater {
          model: root.rows(false)
          delegate: ItemRow { editor: root }
        }

        Row {
          spacing: 6
          height: root.app.ui.target
          Icon { anchors.verticalCenter: parent.verticalCenter; app: root.app; text: KG.plus; size: 18; color: root.app.ui.muted }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "List item"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
          }
          MouseArea {
            width: 200
            height: parent.height
            cursorShape: Qt.PointingHandCursor
            onClicked: root.addItem(-1)
          }
        }

        Item {
          id: tickedHead
          readonly property int count: root.rows(true).length
          visible: count > 0
          width: parent.width
          height: visible ? root.app.ui.target + 8 : 0
          Row {
            anchors.bottom: parent.bottom
            height: root.app.ui.target
            spacing: 6
            Icon {
              anchors.verticalCenter: parent.verticalCenter
              app: root.app
              text: root.showDone ? KG.chevronDown : KG.chevronRight
              size: 18
              color: root.app.ui.muted
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: tickedHead.count + " ticked item" + (tickedHead.count === 1 ? "" : "s")
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.showDone = !root.showDone
          }
        }

        Repeater {
          model: root.showDone ? root.rows(true) : []
          delegate: ItemRow { editor: root }
        }
      }
    }
  }

  // "Edited 19:59", where Keep puts it: on a bar of its own at the bottom,
  // not wherever the text happens to stop.
  Text {
    id: foot
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 12
    x: 18
    text: root.draft ? N.editedLabel(root.stamp) : ""
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
  }
}
