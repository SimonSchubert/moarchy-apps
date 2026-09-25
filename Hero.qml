import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// The first few titles of a list as wide backdrops, one at a time: swipe or
// wait. Advances by itself only while it is on screen and nobody is touching
// it.
Item {
  id: root
  property var app
  property var items: []
  property bool running: true
  property int pad: 16
  // Never more than this of the screen it opens on: the grid should show.
  property real maxHeight: 400

  implicitHeight: items.length ? Math.round(Math.min(app.compact ? (width - pad * 2) * 0.6 : 400, (width - pad * 2) * 0.42, maxHeight)) + 28 : 0
  visible: items.length > 0

  ListView {
    id: strip
    x: root.pad
    width: parent.width - root.pad * 2
    height: parent.height - 28
    orientation: ListView.Horizontal
    snapMode: ListView.SnapOneItem
    highlightRangeMode: ListView.StrictlyEnforceRange
    highlightMoveDuration: 450
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    model: root.items
    cacheBuffer: Math.max(0, width)
    spacing: 0
    reuseItems: false

    delegate: Item {
      id: slide
      required property var modelData
      required property int index
      width: strip.width
      height: strip.height

      Poster {
        anchors.fill: parent
        app: root.app
        source: slide.modelData.fanart || ""
        title: ""
        tint: slide.modelData.tint || ""
        glyph: slide.modelData.type === "show" ? G.tv : G.movie
        radius: root.app.ui.radius + 4
      }

      // Dark enough at the foot for white text on any picture.
      Rectangle {
        anchors.fill: parent
        anchors.margins: 0
        radius: root.app.ui.radius + 4
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
          GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.08) }
          GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.82) }
        }
      }

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.app.compact ? 14 : 26
        spacing: root.app.compact ? 3 : 6

        Rectangle {
          visible: kicker.text !== ""
          width: kicker.implicitWidth + 14
          height: 22
          radius: 11
          color: Qt.rgba(1, 1, 1, 0.18)
          Text {
            id: kicker
            anchors.centerIn: parent
            text: "#" + (slide.index + 1) + (slide.modelData.stat ? "  ·  " + Api.statText(slide.modelData) : "")
            color: "white"
            font.family: root.app.ui.font
            font.pixelSize: 11
            font.weight: Font.DemiBold
          }
        }
        Text {
          width: parent.width
          text: slide.modelData.title || ""
          color: "white"
          font.family: root.app.ui.font
          font.pixelSize: root.app.compact ? 22 : 34
          font.weight: Font.Bold
          elide: Text.ElideRight
          style: Text.Raised
          styleColor: Qt.rgba(0, 0, 0, 0.25)
        }
        Row {
          width: parent.width
          spacing: 6
          Text {
            width: Math.min(implicitWidth, parent.width - (heroPct.visible ? heroPct.implicitWidth + 26 : 0))
            elide: Text.ElideRight
            text: Api.metaLine(slide.modelData)
            color: Qt.rgba(1, 1, 1, 0.85)
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
          Icon {
            visible: heroPct.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            text: G.heart
            size: 12
            width: 14
            color: root.app.ui.heart
          }
          Text {
            id: heroPct
            visible: text !== ""
            text: Api.percent(slide.modelData.rating)
            color: Qt.rgba(1, 1, 1, 0.85)
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
        }
        Text {
          visible: !root.app.compact && text !== ""
          width: Math.min(parent.width, 640)
          text: slide.modelData.overview || ""
          color: Qt.rgba(1, 1, 1, 0.78)
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
          lineHeight: 1.15
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.app.openMedia(slide.modelData)
      }
    }
  }

  // Where you are among them.
  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 9
    spacing: 6
    Repeater {
      model: root.items.length
      delegate: Rectangle {
        required property int index
        width: index === strip.currentIndex ? 18 : 6
        height: 6
        radius: 3
        color: index === strip.currentIndex ? root.app.ui.accent : root.app.alpha(root.app.ui.text, 0.25)
        Behavior on width { NumberAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: strip.currentIndex = parent.index }
      }
    }
  }

  Timer {
    interval: 7000
    repeat: true
    running: root.running && root.visible && root.items.length > 1 && !strip.moving && !strip.dragging
    onTriggered: strip.currentIndex = (strip.currentIndex + 1) % root.items.length
  }

  onItemsChanged: if (strip.currentIndex >= items.length) strip.currentIndex = 0
}
