import QtQuick
import "kit"
import "Notes.js" as N
import "Glyphs.js" as G

// Every note, in the two sections Keep has: pinned, then the rest, newest
// edited first. Masonry columns -- two on a phone, as many as fit on a
// desktop, one in the list view -- each card placed in the shortest column so
// far, so a long note does not leave a hole beside it.
Item {
  id: root
  property var app

  readonly property var sections: N.sections(app.notes, app.query)
  readonly property bool nothing: !sections.pinned.length && !sections.others.length
  // The headings only earn their line when there is a division to explain:
  // with nothing pinned, "Others" would label the whole app.
  readonly property bool labelled: sections.pinned.length > 0 && sections.others.length > 0 && app.query.trim() === ""
  readonly property int cols: app.notes.view === "list" ? 1
    : app.compact ? 2 : Math.max(2, Math.min(5, Math.floor(flick.width / 230)))
  readonly property real laneWidth: app.notes.view === "list" && !app.compact ? Math.min(flick.width - 2 * app.ui.gutter, 640)
    : flick.width - 2 * app.ui.gutter

  function focusSearch() { search.input.forceActiveFocus() }

  SearchField {
    id: search
    app: root.app
    x: (parent.width - width) / 2
    y: 4
    width: Math.min(parent.width - 2 * root.app.ui.gutter, 640)
    placeholder: "Search your notes"
    text: root.app.query
    onTextChanged: root.app.query = text
    onEscaped: { text = ""; root.app.resetFocus() }
  }

  // "Take a note…": at the bottom on a phone, where a thumb is, and under the
  // search on a desktop.
  TakeBar {
    id: topBar
    app: root.app
    visible: !root.app.compact
    anchors.top: search.bottom
    anchors.topMargin: 10
    x: search.x
    width: search.width
  }

  Flickable {
    id: flick
    anchors.top: root.app.compact ? search.bottom : topBar.bottom
    anchors.topMargin: 10
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: root.app.compact ? bottomBar.top : parent.bottom
    contentWidth: width
    contentHeight: lanes.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: lanes
      x: (flick.width - width) / 2
      width: root.laneWidth
      spacing: 8

      Repeater {
        model: [
          { title: "Pinned", notes: root.sections.pinned },
          { title: "Others", notes: root.sections.others }
        ]
        delegate: Column {
          id: section
          required property var modelData
          visible: modelData.notes.length > 0
          width: lanes.width
          spacing: 8

          Text {
            visible: root.labelled
            topPadding: 6
            text: section.modelData.title
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.8
          }

          Row {
            spacing: 10
            Repeater {
              model: N.columns(section.modelData.notes, root.cols)
              delegate: Column {
                id: lane
                required property var modelData
                width: (lanes.width - (root.cols - 1) * 10) / root.cols
                spacing: 10
                Repeater {
                  model: lane.modelData
                  delegate: NoteCard {
                    required property var modelData
                    width: lane.width
                    app: root.app
                    note: modelData
                    selected: root.app.openId === modelData.id
                    onOpened: root.app.openNote(modelData.id, false)
                    onMenu: root.app.cardMenu(modelData.id)
                  }
                }
              }
            }
          }
        }
      }
    }

    EmptyState {
      visible: root.nothing
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.max(40, flick.height / 2 - height / 2 - 40)
      app: root.app
      glyph: root.app.query.trim() ? "" : G.empty
      title: root.app.query.trim() ? "No matching notes" : "Notes you add appear here"
      text: root.app.query.trim()
        ? "Nothing here matches “" + root.app.query.trim() + "”"
        : "Tap “Take a note…” to write one, or the tick box for a list."
    }
  }

  TakeBar {
    id: bottomBar
    app: root.app
    visible: root.app.compact
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 10
    x: root.app.ui.gutter
    width: parent.width - 2 * root.app.ui.gutter
  }
}
