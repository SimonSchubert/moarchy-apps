import QtQuick
import "kit"
import "Glyphs.js" as G
import "Lbry.js" as L

// One video in a grid: the picture with its length on it, then the channel's
// face, the title in two lines, and who and when. The card opens the video;
// the face is its own target and opens the channel.
Item {
  id: root
  property var app
  property var item: null
  property real now: 0
  property bool saved: false
  property bool current: false
  signal opened()
  signal channelOpened()

  readonly property var ch: item ? item.channel : null
  readonly property int face: app.compact ? 36 : 32

  Accessible.role: Accessible.ListItem
  Accessible.name: item ? item.title + ", " + L.byline(item, now) : ""

  Rectangle {
    anchors.fill: parent
    anchors.margins: -6
    radius: root.app.ui.radius
    color: mouse.pressed ? root.app.ui.pressed : mouse.containsMouse ? root.app.ui.hover : "transparent"
    border.width: root.current && !root.app.compact ? 1 : 0
    border.color: root.app.ui.accent
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened()
  }

  Thumb {
    id: pic
    width: parent.width
    height: Math.round(width * 9 / 16)
    app: root.app
    source: root.item ? root.app.art(root.item.id, root.item.thumb, 390, 220) : ""
    glyph: root.item && root.item.kind === "audio" ? G.audio : G.video

    // The length, bottom right, on a scrim that reads over any picture.
    Rectangle {
      visible: len.text !== ""
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 7
      width: len.implicitWidth + 10
      height: 20
      radius: root.app.ui.radius > 0 ? 3 : 0
      color: root.app.ui.scrimStrong
      Text {
        id: len
        anchors.centerIn: parent
        text: root.item ? L.duration(root.item.duration) : ""
        color: root.app.ui.scrimInk
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        font.weight: Font.Bold
        font.features: ({ "tnum": 1 })
      }
    }

    // Top left: what kind of thing it is, when that is not a free video.
    Row {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.margins: 7
      spacing: 4
      Rectangle {
        visible: !!root.item && root.item.kind === "audio"
        width: 22; height: 20
        radius: root.app.ui.radius > 0 ? 3 : 0
        color: root.app.ui.scrimStrong
        Icon { anchors.centerIn: parent; app: root.app; text: G.audio; size: 12; color: root.app.ui.scrimInk }
      }
      Rectangle {
        visible: !!root.item && !L.playable(root.item)
        width: lock.implicitWidth + 12; height: 20
        radius: root.app.ui.radius > 0 ? 3 : 0
        color: root.app.ui.scrimStrong
        Text {
          id: lock
          anchors.centerIn: parent
          text: root.item && root.item.members ? "MEMBERS" : "PAID"
          color: root.app.ui.warn
          font.family: root.app.ui.font
          font.pixelSize: 10
          font.weight: Font.Bold
          font.letterSpacing: 0.8
        }
      }
    }

    Rectangle {
      visible: root.saved
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 7
      width: 22; height: 22
      radius: root.app.ui.radius > 0 ? 3 : 0
      color: root.app.ui.accent
      Icon { anchors.centerIn: parent; app: root.app; text: G.saved; size: 13; color: root.app.ui.inkOnAccent }
    }
  }

  Thumb {
    id: avatar
    anchors.top: pic.bottom
    anchors.topMargin: 10
    width: root.face
    height: root.face
    app: root.app
    glyph: G.channel
    glyphSize: 16
    source: root.ch ? root.app.art(root.ch.id, root.ch.thumb, 96, 96) : ""
    MouseArea {
      anchors.fill: parent
      anchors.margins: -4
      enabled: root.ch !== null
      cursorShape: Qt.PointingHandCursor
      onClicked: root.channelOpened()
    }
  }

  Column {
    anchors.top: pic.bottom
    anchors.topMargin: 9
    anchors.left: avatar.right
    anchors.leftMargin: 10
    anchors.right: parent.right
    spacing: 3
    Text {
      width: parent.width
      text: root.item ? root.item.title : ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md + 1
      font.weight: Font.Bold
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
      lineHeight: 1.1
    }
    Text {
      width: parent.width
      text: L.byline(root.item, root.now)
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      elide: Text.ElideRight
    }
  }
}
