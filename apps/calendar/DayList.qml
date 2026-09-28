pragma ComponentBehavior: Bound

import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Dates.js" as Dates

// The selected day: its name, and what is on it. Under the grid on a phone,
// beside it on a desktop, so tapping the 14th answers "what is on the 14th"
// without going anywhere.
Item {
  id: root
  property var app

  Item {
    id: head
    width: parent.width
    height: root.app.ui.target + 8

    Column {
      anchors.left: parent.left
      anchors.leftMargin: root.app.ui.gutter
      anchors.right: addButton.left
      anchors.verticalCenter: parent.verticalCenter
      // "# Today", as Omarchy heads a group, and the date under it.
      SectionTitle {
        app: root.app
        height: 22
        text: Dates.headline(root.app.selected, root.app.today)
      }
      Text {
        width: parent.width
        visible: text.length > 0
        text: Dates.relative(root.app.selected, root.app.today).length ? Dates.dayLabel(root.app.selected) : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        elide: Text.ElideRight
      }
    }
    Button {
      id: addButton
      visible: !root.app.compact
      anchors.right: parent.right
      anchors.rightMargin: root.app.ui.gutter
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      glyph: KG.plus
      text: "New event"
      onClicked: root.app.startNew()
    }
  }

  Flickable {
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    contentWidth: width
    contentHeight: list.height + 16
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: list
      x: root.app.ui.gutter
      width: parent.width - root.app.ui.gutter * 2
      spacing: 8

      Repeater {
        model: root.app.opened ? root.app.selectedEvents : []
        delegate: EventRow {
          required property var modelData
          app: root.app
          width: list.width
          entry: modelData
          selected: !!root.app.draft && root.app.draft.id === modelData.id
          onClicked: root.app.startEdit(modelData)
        }
      }

      // Nothing on. Not a blank half-screen: the empty state is most of what
      // a new calendar is, and the only place to say where events come from.
      Item {
        visible: root.app.selectedEvents.length === 0
        width: list.width
        height: empty.implicitHeight + 32
        EmptyState {
          id: empty
          app: root.app
          y: 16
          anchors.horizontalCenter: parent.horizontalCenter
          glyph: G.empty
          title: root.app.selected === root.app.today ? "Nothing today" : "Nothing on " + Dates.dayLabel(root.app.selected)
          text: root.app.events.length ? "" : (root.app.compact ? "The plus puts something in the day." : "New event puts something in the day.")
        }
      }
    }
  }
}
