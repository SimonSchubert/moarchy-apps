import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Lbry.js" as L

// One video, from the claim already in hand: the picture with a play button
// on it, the title, the channel with its follow button, what can be done
// with it, what the uploader wrote, and the rest of the channel. Nothing is
// asked for but that last list.
//
// Wide, the facts and the channel's other videos sit in a column beside it,
// the way a video site lays out a watch page; narrow, under it.
Item {
  id: root
  property var app
  property var item: null
  property real now: 0
  property bool saved: false
  property bool followed: false
  property bool playing: false
  property var related: []
  property bool relatedLoading: false
  signal play(bool audioOnly)
  signal stop()
  signal saveToggled()
  signal followToggled()
  signal channelOpened()
  signal videoOpened(var item)
  signal tagSearched(string tag)

  readonly property var ch: item ? item.channel : null
  readonly property bool canPlay: L.playable(item)
  readonly property bool wide: flick.width >= 980
  readonly property real sideWidth: wide ? 340 : 0
  readonly property real mainWidth: Math.min((wide ? flick.width - sideWidth - 3 * root.app.ui.gutter : flick.width - 2 * root.app.ui.gutter), 1000)
  property bool expanded: false

  onItemChanged: { expanded = false; flick.contentY = 0 }

  PageHeader {
    id: head
    width: parent.width
    app: root.app
    title: root.ch ? root.ch.title : "Video"
    subtitle: root.item ? L.ago(root.item.released, root.now) : ""
    IconButton {
      app: root.app
      glyph: root.saved ? G.saved : G.save
      color: root.saved ? root.app.ui.accent : root.app.ui.text
      label: root.saved ? "Remove from Saved" : "Save for later"
      onClicked: root.saveToggled()
    }
    IconButton {
      app: root.app
      glyph: G.copy
      label: "Copy the Odysee link"
      onClicked: root.app.copyLink(root.item ? root.item.url : "")
    }
    IconButton {
      app: root.app
      glyph: KG.open
      label: "Open on odysee.com"
      onClicked: root.app.openWeb(root.item ? root.item.url : "")
    }
  }

  Flickable {
    id: flick
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: Math.max(main.y + main.implicitHeight, side.y + side.implicitHeight) + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: main
      x: root.app.ui.gutter
      y: root.app.compact ? 12 : 20
      width: root.mainWidth
      spacing: 14

      // ------------------------------------------------ the picture
      // The video plays here; fullscreen lifts it out of this box.
      Item {
        id: heroSlot
        width: parent.width
        height: Math.round(width * 9 / 16)
        VideoSurface {
          app: root.app
          item: root.item
          slot: heroSlot
        }
      }

      // ------------------------------------------------ what it is
      Column {
        width: parent.width
        spacing: 6
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: root.item ? root.item.title : ""
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.compact ? root.app.ui.fs.lg + 2 : root.app.ui.fs.xl - 4
          font.weight: Font.Bold
          lineHeight: 1.1
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: root.item ? [L.ago(root.item.released, root.now), L.duration(root.item.duration), L.resolution(root.item)]
            .filter(function (s) { return s !== "" }).join("  ·  ") : ""
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }

      // ------------------------------------------------ who
      Rectangle {
        width: parent.width
        height: 68
        visible: root.ch !== null
        radius: root.app.ui.radius
        color: chMouse.pressed ? root.app.ui.pressed : chMouse.containsMouse ? root.app.ui.hover : root.app.ui.surface
        border.width: 1
        border.color: root.app.ui.line

        MouseArea {
          id: chMouse
          anchors.fill: parent
          hoverEnabled: !root.app.compact
          cursorShape: Qt.PointingHandCursor
          onClicked: root.channelOpened()
        }
        Thumb {
          id: chFace
          x: 12
          anchors.verticalCenter: parent.verticalCenter
          width: 44; height: 44
          app: root.app
          glyph: G.channel
          glyphSize: 18
          source: root.ch ? root.app.art(root.ch.id, root.ch.thumb, 96, 96) : ""
        }
        Column {
          anchors.left: chFace.right
          anchors.leftMargin: 12
          anchors.right: followBtn.left
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            width: parent.width
            text: root.ch ? root.ch.title : ""
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md + 1
            font.weight: Font.Bold
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: root.ch ? [L.handle(root.ch), L.uploadsText(root.ch)].filter(function (s) { return s !== "" }).join(" · ") : ""
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            elide: Text.ElideRight
          }
        }
        Button {
          id: followBtn
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          primary: !root.followed
          active: root.followed
          glyph: root.followed ? G.followed : G.follow
          text: root.followed ? "Following" : "Follow"
          onClicked: root.followToggled()
        }
      }

      // ------------------------------------------------ what to do
      Flow {
        width: parent.width
        spacing: 8
        Button {
          app: root.app
          primary: !root.playing
          active: root.playing
          enabled: root.canPlay
          readonly property bool going: root.app.mediaPlaying || root.app.mediaBusy
          glyph: root.playing && going ? KG.pause : KG.play
          text: !root.playing ? "Play" : going ? "Pause" : "Resume"
          onClicked: root.playing ? root.app.togglePause() : root.play(false)
        }
        Button {
          visible: !!root.item && root.item.kind === "video"
          app: root.app
          enabled: root.canPlay
          glyph: G.audio
          text: "Listen"
          onClicked: root.play(true)
        }
        Button {
          app: root.app
          active: root.saved
          glyph: root.saved ? G.saved : G.save
          text: root.saved ? "Saved" : "Save"
          onClicked: root.saveToggled()
        }
        Button {
          app: root.app
          glyph: G.copy
          text: "Link"
          onClicked: root.app.copyLink(root.item ? root.item.url : "")
        }
        Button {
          app: root.app
          enabled: root.canPlay
          glyph: G.external
          text: "mpv"
          onClicked: root.app.openInMpv(root.item)
        }
      }

      // ------------------------------------------------ what they wrote
      Rectangle {
        width: parent.width
        visible: desc.text !== ""
        height: descCol.implicitHeight + 28
        radius: root.app.ui.radius
        color: root.app.ui.surface
        border.width: 1
        border.color: root.app.ui.line
        Column {
          id: descCol
          x: 14; y: 14
          width: parent.width - 28
          spacing: 8
          Text {
            id: desc
            width: parent.width
            wrapMode: Text.Wrap
            text: root.item ? root.item.description : ""
            maximumLineCount: root.expanded ? 400 : 6
            elide: Text.ElideRight
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            lineHeight: 1.2
          }
          Text {
            visible: desc.truncated || root.expanded
            text: root.expanded ? "Show less" : "Show more"
            color: root.app.ui.accent
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: root.app.ui.tracking
            MouseArea {
              anchors.fill: parent
              anchors.margins: -10
              cursorShape: Qt.PointingHandCursor
              onClicked: root.expanded = !root.expanded
            }
          }
        }
      }

      Flow {
        width: parent.width
        spacing: 6
        visible: !!root.item && root.item.tags.length > 0
        Repeater {
          model: root.item ? root.item.tags : []
          delegate: Chip {
            required property string modelData
            app: root.app
            text: "#" + modelData
            hpad: 16
            onClicked: root.tagSearched(modelData)
          }
        }
      }

      Loader {
        width: parent.width
        active: !root.wide
        visible: active
        sourceComponent: sideBody
      }
    }

    Loader {
      id: side
      x: main.x + main.width + root.app.ui.gutter
      y: main.y
      width: root.sideWidth
      active: root.wide
      visible: active
      sourceComponent: sideBody
    }
  }

  // The facts, and more from the same channel: beside the video when there
  // is room, under it when there is not.
  Component {
    id: sideBody
    Column {
      id: sideCol
      width: parent ? parent.width : 0
      spacing: 14
      readonly property var facts: L.facts(root.item)

      Rectangle {
        width: parent.width
        visible: sideCol.facts.length > 0
        height: factGrid.implicitHeight + 28
        radius: root.app.ui.radius
        color: root.app.ui.surface
        border.width: 1
        border.color: root.app.ui.line
        Grid {
          id: factGrid
          x: 14; y: 14
          width: parent.width - 28
          columns: 2
          rowSpacing: 12
          columnSpacing: 12
          Repeater {
            model: sideCol.facts
            delegate: Column {
              required property var modelData
              width: (factGrid.width - factGrid.columnSpacing) / 2
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
                maximumLineCount: 2
                elide: Text.ElideRight
                text: modelData.value
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.md
                font.weight: Font.Bold
              }
            }
          }
        }
      }

      SectionTitle {
        visible: root.ch !== null && (root.related.length > 0 || root.relatedLoading)
        app: root.app
        text: "More from " + (root.ch ? root.ch.title : "")
        width: parent.width
        clip: true
      }

      Spinner {
        visible: root.relatedLoading && root.related.length === 0
        running: visible
        app: root.app
        anchors.horizontalCenter: parent.horizontalCenter
      }

      Repeater {
        model: root.related
        delegate: Rectangle {
          id: rel
          required property var modelData
          width: parent.width
          height: relPic.height + 12
          radius: root.app.ui.radius
          color: relMouse.pressed ? root.app.ui.pressed : relMouse.containsMouse ? root.app.ui.hover : "transparent"
          MouseArea {
            id: relMouse
            anchors.fill: parent
            hoverEnabled: !root.app.compact
            cursorShape: Qt.PointingHandCursor
            onClicked: root.videoOpened(rel.modelData)
          }
          Thumb {
            id: relPic
            x: 6; y: 6
            width: 136
            height: 76
            app: root.app
            glyph: G.video
            glyphSize: 18
            source: root.app.art(rel.modelData.id, rel.modelData.thumb, 272, 152)
            Rectangle {
              visible: relLen.text !== ""
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 4
              width: relLen.implicitWidth + 8
              height: 17
              color: root.app.ui.scrimStrong
              radius: root.app.ui.radius > 0 ? 3 : 0
              Text {
                id: relLen
                anchors.centerIn: parent
                text: L.duration(rel.modelData.duration)
                color: root.app.ui.scrimInk
                font.family: root.app.ui.font
                font.pixelSize: 10
                font.weight: Font.Bold
              }
            }
          }
          Column {
            anchors.left: relPic.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.top: relPic.top
            spacing: 4
            Text {
              width: parent.width
              text: rel.modelData.title
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm + 1
              font.weight: Font.Bold
              wrapMode: Text.Wrap
              maximumLineCount: 3
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: L.ago(rel.modelData.released, root.now)
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xs + 1
            }
          }
        }
      }
    }
  }
}
