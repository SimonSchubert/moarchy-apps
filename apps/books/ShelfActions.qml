import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "OpenLibrary.js" as OL

// What you can do with a book: put it on one of the three shelves (the one
// it is on, tapped again, takes it off), and then -- reading it -- say how
// far you are, or -- having read it -- give it your stars.
//
// Three buttons in a row under a phone's cover; stacked, under the cover in
// a desktop's side column.
Column {
  id: root
  property var app
  property var book: null
  property var entry: null
  property bool stacked: false

  readonly property string shelf: entry ? entry.shelf : ""
  spacing: 12

  Grid {
    id: buttons
    width: parent.width
    columns: root.stacked ? 1 : 3
    spacing: root.stacked ? 8 : 6
    readonly property real cell: (width - spacing * (columns - 1)) / columns
    Repeater {
      model: [
        { key: "want", long: "Want to read", short: "Want", glyph: G.want, on: G.wanted },
        { key: "reading", long: "Reading", short: "Reading", glyph: G.reading, on: G.reading },
        { key: "read", long: "Read", short: "Read", glyph: G.read, on: KG.check }
      ]
      delegate: Button {
        required property var modelData
        width: buttons.cell
        app: root.app
        text: root.stacked || !root.app.compact ? modelData.long : modelData.short
        glyph: root.shelf === modelData.key ? modelData.on : modelData.glyph
        active: root.shelf === modelData.key
        primary: root.shelf === "" && modelData.key === "want"
        tint: modelData.key === "read" && root.shelf === "read" ? root.app.ui.good : root.app.ui.accent
        onClicked: if (root.book) root.app.shelve(root.book, modelData.key)
      }
    }
  }

  // ------------------------------------------------ how far
  Rectangle {
    visible: root.shelf === "reading"
    width: parent.width
    height: progressCol.implicitHeight + 24
    radius: root.app.ui.radius
    color: root.app.ui.surface
    border.width: 1
    border.color: root.app.ui.line

    Column {
      id: progressCol
      x: 12
      y: 12
      width: parent.width - 24
      spacing: 10
      Row {
        spacing: 6
        IconButton {
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          glyph: KG.minus
          label: "Ten pages back"
          onClicked: if (root.entry) root.app.setPage(root.entry.id, (root.entry.page || 0) - 10)
        }
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 72
          height: root.app.compact ? 40 : 34
          radius: root.app.ui.radius
          color: root.app.ui.bg
          border.width: 1
          border.color: pageInput.activeFocus ? root.app.ui.accent : root.app.ui.line
          TextInput {
            id: pageInput
            anchors.fill: parent
            anchors.margins: 6
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            text: root.entry ? String(root.entry.page || 0) : "0"
            color: root.app.ui.text
            selectionColor: root.app.ui.accent
            selectedTextColor: root.app.ui.inkOnAccent
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md + 1
            font.weight: Font.Bold
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator { bottom: 0; top: 99999 }
            activeFocusOnPress: true
            selectByMouse: true
            Accessible.name: "Page"
            function commit() { if (root.entry && text !== "") root.app.setPage(root.entry.id, parseInt(text, 10)) }
            onEditingFinished: commit()
            Keys.onEscapePressed: function (event) { root.app.resetFocus(); event.accepted = true }
            Keys.onReturnPressed: function (event) { commit(); root.app.resetFocus(); event.accepted = true }
            Keys.onEnterPressed: function (event) { commit(); root.app.resetFocus(); event.accepted = true }
          }
        }
        IconButton {
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          glyph: KG.plus
          label: "Ten pages on"
          onClicked: if (root.entry) root.app.setPage(root.entry.id, (root.entry.page || 0) + 10)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.entry && root.entry.pages > 0 ? "of " + OL.grouped(root.entry.pages) : "pages in"
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }
      Rectangle {
        visible: root.entry && root.entry.pages > 0
        width: parent.width
        height: 6
        radius: root.app.ui.radius > 0 ? 3 : 0
        color: root.app.ui.well
        Rectangle {
          width: parent.width * OL.progress(root.entry)
          height: parent.height
          radius: parent.radius
          color: root.app.ui.accent
          Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.entry ? [root.entry.pages > 0 ? Math.round(OL.progress(root.entry) * 100) + "% through" : "",
                            root.entry.started ? "started " + OL.date(root.entry.started) : ""]
                            .filter(function (s) { return s !== "" }).join("  ·  ") : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
    }
  }

  // ------------------------------------------------ what you made of it
  Rectangle {
    visible: root.shelf === "read"
    width: parent.width
    height: readCol.implicitHeight + 24
    radius: root.app.ui.radius
    color: root.app.ui.surface
    border.width: 1
    border.color: root.app.ui.line

    Column {
      id: readCol
      x: 12
      y: 12
      width: parent.width - 24
      spacing: 6
      Text {
        text: "Your stars"
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: root.app.ui.tracking
      }
      Stars {
        app: root.app
        interactive: true
        size: 22
        value: root.entry ? root.entry.stars || 0 : 0
        onPicked: function (n) { if (root.entry) root.app.setStars(root.entry.id, n) }
      }
      Text {
        visible: text !== ""
        text: root.entry && root.entry.finished ? "Finished " + OL.date(root.entry.finished) : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
    }
  }
}
