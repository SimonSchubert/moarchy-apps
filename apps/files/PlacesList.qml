import QtQuick
import "kit"
import "Glyphs.js" as G
import "Listing.js" as Listing

// Home, the folders that exist, the trash, then the volumes, with how full each
// volume is -- the only question anybody has ever asked about one. A page of
// its own on a phone, the column beside the list on a desktop.
Flickable {
  id: root
  property var app
  property var rows: []
  // The place the list is showing, lit on a desktop.
  property string current: ""
  signal go(string path)

  contentWidth: width
  contentHeight: col.implicitHeight + 16
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  Column {
    id: col
    x: root.app.compact ? root.app.ui.gutter : 8
    y: root.app.compact ? 4 : 8
    width: root.width - x * 2
    spacing: 2

    Repeater {
      model: root.rows
      delegate: Rectangle {
        id: place
        required property var modelData
        readonly property bool here: root.current === modelData.path
        readonly property real used: modelData.total > 0 ? 1 - modelData.free / modelData.total : 0
        width: col.width
        height: root.app.compact ? (modelData.volume ? 72 : 56) : (modelData.volume ? 60 : 40)
        radius: root.app.ui.radius
        color: here && !root.app.compact ? root.app.ui.accentSoft
          : mouse.pressed ? root.app.ui.pressed : mouse.containsMouse ? root.app.ui.hover : "transparent"

        Icon {
          id: glyph
          app: root.app
          x: 8
          anchors.verticalCenter: parent.verticalCenter
          text: G.of([place.modelData.glyph, "folder-symbolic"])
          size: root.app.compact ? 20 : 18
          color: root.app.ui.accent
        }
        Column {
          anchors.left: glyph.right
          anchors.leftMargin: 8
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          spacing: 3
          Text {
            width: parent.width
            text: place.modelData.label
            color: place.here && !root.app.compact ? root.app.ui.accent : root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: place.here && !root.app.compact ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
          }
          Text {
            visible: root.app.compact && !place.modelData.volume && place.modelData.note !== ""
            width: parent.width
            text: place.modelData.note
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            elide: Text.ElideMiddle
          }
          Text {
            visible: !!place.modelData.volume
            text: Listing.human(place.modelData.free) + " free of " + Listing.human(place.modelData.total)
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
          Rectangle {
            visible: !!place.modelData.volume
            width: parent.width
            height: 5
            radius: 2.5
            color: root.app.ui.well
            Rectangle {
              width: Math.max(parent.height, parent.width * place.used)
              height: parent.height
              radius: parent.radius
              color: place.used >= 0.9 ? root.app.ui.bad : place.used >= 0.75 ? root.app.ui.warn : root.app.ui.accent
            }
          }
        }
        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: !root.app.compact
          cursorShape: Qt.PointingHandCursor
          onClicked: root.go(place.modelData.path)
        }
      }
    }
  }
}
