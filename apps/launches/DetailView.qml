import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Launches.js" as L

// One launch, out of the answer already in memory -- no second request: its
// status, the countdown in large, the facts that were sent, and the mission.
//
// `paged` is a page of its own on a phone, with a back arrow; otherwise it is
// the pane beside the list on a desktop, with a close button.
Item {
  id: root
  property var app
  property var item: null
  property bool starred: false
  property bool paged: false
  property real now: 0
  signal starToggled()
  signal closed()

  readonly property var facts: L.facts(item)

  PageHeader {
    id: head
    visible: root.paged
    width: parent.width
    height: visible ? implicitHeight : 0
    app: root.app
    title: root.item ? root.item.name : ""
    subtitle: root.item ? (root.item.vehicle || root.item.agency) : ""
    IconButton {
      app: root.app
      glyph: root.starred ? KG.star : KG.starOutline
      color: root.starred ? root.app.ui.star : root.app.ui.text
      label: root.starred ? "Unstar" : "Star"
      onClicked: root.starToggled()
    }
  }

  Row {
    id: paneHead
    visible: !root.paged
    anchors.right: parent.right
    anchors.rightMargin: 12
    y: 12
    height: visible ? implicitHeight : 0
    spacing: 2
    z: 2
    IconButton {
      app: root.app
      glyph: root.starred ? KG.star : KG.starOutline
      color: root.starred ? root.app.ui.star : root.app.ui.text
      label: root.starred ? "Unstar" : "Star"
      onClicked: root.starToggled()
    }
    IconButton {
      app: root.app
      glyph: KG.close
      label: "Close"
      onClicked: root.closed()
    }
  }

  Flickable {
    id: flick
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: body.implicitHeight + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      x: root.app.ui.gutter
      y: root.paged ? 4 : 20
      width: Math.min(flick.width - x * 2, 640)
      spacing: 14

      Row {
        width: parent.width - (root.paged ? 0 : 100)
        spacing: 14
        StatusBadge {
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          item: root.item
          size: 48
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 62
          spacing: 2
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: root.item ? root.item.name : ""
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.lg + 2
            font.weight: Font.Bold
          }
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            visible: text !== ""
            text: L.note(root.item)
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
        }
      }

      Text {
        text: root.item ? L.headline(root.item, root.now) : ""
        color: root.app.ui.tone(L.tone(root.item, root.now))
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xl
        font.weight: Font.Bold
        font.features: ({ "tnum": 1 })
      }

      Card {
        app: root.app
        width: parent.width
        visible: root.facts.length > 0
        Repeater {
          model: root.facts
          delegate: Column {
            required property var modelData
            width: parent.width
            spacing: 2
            Text {
              text: modelData.label
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xs
              font.capitalization: Font.AllUppercase
              font.letterSpacing: root.app.ui.tracking
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: modelData.value
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
              font.weight: Font.Bold
            }
          }
        }
      }

      Text {
        width: parent.width
        visible: !!(root.item && root.item.description)
        wrapMode: Text.Wrap
        lineHeight: 1.2
        text: root.item ? root.item.description : ""
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
      }
    }
  }
}
