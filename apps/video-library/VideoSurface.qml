import QtQuick
import QtMultimedia
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Lbry.js" as L

// Where a video plays: in the page, in the box its picture was in, or over
// the whole window when asked. Before it plays it is the picture with a play
// button; while it plays it is the video with controls a finger can use --
// tap for them, double-tap a side to skip ten seconds, drag the line to seek.
//
// There is one player, the app's (Panel's `media`); this surface lends it
// its VideoOutput while it shows the video that is playing. Leaving the page
// keeps the sound going, and the bar at the bottom of the tabs has it.
//
// Fullscreen is this same item moved into the app's overlay, so the video
// never stops or reloads to change size. A landscape video on a portrait
// screen turns on its side there, which is how a phone is held for one.
Rectangle {
  id: root
  property var app
  property var item: null

  readonly property bool active: item !== null && app.playingItem !== null && app.playingItem.id === item.id
  readonly property bool full: active && app.fullscreen
  readonly property bool canPlay: L.playable(item)
  readonly property var media: app.media
  readonly property bool playing: active && app.mediaPlaying
  readonly property bool busy: active && app.mediaBusy
  // A frame is up: until then the picture stays, rather than a black box.
  readonly property bool showing: active && !app.playingAudio && media.hasVideo
    && media.mediaStatus !== MediaPlayer.LoadingMedia

  property Item slot: null
  parent: full ? app.overlay : slot
  anchors.fill: parent
  color: full ? "black" : app.ui.well
  radius: full ? 0 : app.ui.radius
  border.width: full ? 0 : 1
  border.color: app.ui.line
  clip: true

  // The player's picture goes to whichever surface shows the playing video.
  function claim() { if (active && !app.playingAudio) media.videoOutput = out }
  onActiveChanged: claim()
  Component.onCompleted: claim()
  Connections {
    target: root.app
    function onPlayingAudioChanged() { root.claim() }
  }

  // ------------------------------------------------------------ controls
  property bool controls: true
  function poke() { controls = true; hide.restart() }
  Timer {
    id: hide
    interval: 3200
    onTriggered: if (root.playing && !seeker.dragging) root.controls = false
  }
  onPlayingChanged: playing ? hide.restart() : (controls = true)

  // Everything turns together, the controls with the picture.
  Item {
    id: stage
    readonly property bool turn: root.full && root.width < root.height && root.landscape
    anchors.centerIn: parent
    width: turn ? root.height : root.width
    height: turn ? root.width : root.height
    rotation: turn ? 90 : 0

    Thumb {
      anchors.fill: parent
      visible: !root.showing
      app: root.app
      color: "transparent"
      border.width: 0
      glyph: root.item && root.item.kind === "audio" ? G.audio : G.video
      glyphSize: 48
      source: root.item ? root.app.art(root.item.id, root.item.thumb, 960, 540) : ""
    }

    VideoOutput {
      id: out
      anchors.fill: parent
      visible: root.showing
      fillMode: VideoOutput.PreserveAspectFit
    }

    // Taps: one shows or hides the controls, two on a side skip ten seconds.
    TapHandler {
      enabled: root.active
      onSingleTapped: root.controls ? (root.controls = false) : root.poke()
      onDoubleTapped: function (point) {
        var right = point.position.x > stage.width / 2
        root.app.seekBy(right ? 10000 : -10000)
        skipped.text = right ? "+10 s" : "−10 s"
        skipped.x = right ? stage.width * 0.75 - skipped.width / 2 : stage.width * 0.25 - skipped.width / 2
        skipFlash.restart()
        root.poke()
      }
    }

    Text {
      id: skipped
      anchors.verticalCenter: parent.verticalCenter
      opacity: 0
      color: root.app.ui.scrimInk
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.lg + 4
      font.weight: Font.Bold
      style: Text.Outline
      styleColor: root.app.ui.scrimStrong
      SequentialAnimation on opacity {
        id: skipFlash
        running: false
        NumberAnimation { to: 1; duration: 80 }
        PauseAnimation { duration: 420 }
        NumberAnimation { to: 0; duration: 260 }
      }
    }

    // ---------------------------------------------- not playing: a button
    Rectangle {
      visible: !root.active
      anchors.centerIn: parent
      width: root.canPlay ? (root.app.compact ? 64 : 76) : lockRow.implicitWidth + 28
      height: root.app.compact ? 64 : 76
      radius: root.app.ui.radius
      color: root.canPlay ? root.app.ui.accent : root.app.ui.scrimStrong
      border.width: 1
      border.color: root.app.ui.alpha(root.app.ui.scrimInk, 0.25)
      Icon {
        visible: root.canPlay
        anchors.centerIn: parent
        app: root.app
        text: KG.play
        size: root.app.compact ? 34 : 40
        color: root.app.ui.inkOnAccent
      }
      Row {
        id: lockRow
        visible: !root.canPlay
        anchors.centerIn: parent
        spacing: 8
        Icon { anchors.verticalCenter: parent.verticalCenter; app: root.app; text: G.locked; size: 20; color: root.app.ui.scrimInk }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.item && root.item.members ? "For the channel's members" : "Paid: buy it on Odysee"
          color: root.app.ui.scrimInk
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: Font.Bold
        }
      }
      MouseArea {
        anchors.fill: parent
        anchors.margins: -20
        enabled: root.canPlay
        cursorShape: Qt.PointingHandCursor
        onClicked: root.app.play(root.item, false)
      }
    }

    Rectangle {
      visible: !root.active && len.text !== ""
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 10
      width: len.implicitWidth + 12
      height: 22
      radius: root.app.ui.radius > 0 ? 3 : 0
      color: root.app.ui.scrimStrong
      Text {
        id: len
        anchors.centerIn: parent
        text: root.item ? L.duration(root.item.duration) : ""
        color: root.app.ui.scrimInk
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
        font.weight: Font.Bold
        font.features: ({ "tnum": 1 })
      }
    }

    Text {
      visible: root.active && root.app.playingAudio
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: 14
      text: "LISTENING · SOUND ONLY"
      color: root.app.ui.scrimInk
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.weight: Font.Bold
      font.letterSpacing: root.app.ui.tracking
      style: Text.Outline
      styleColor: root.app.ui.scrimStrong
    }

    // ---------------------------------------------- playing: the controls
    Item {
      id: chrome
      anchors.fill: parent
      visible: opacity > 0
      opacity: root.active && (root.controls || !root.playing) ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 160 } }

      Rectangle {
        anchors.fill: parent
        color: root.app.ui.alpha(root.app.ui.scrimStrong, 0.45)
      }

      // Back out of fullscreen, top left, where a back button is.
      IconButton {
        visible: root.full
        x: 8; y: 8
        app: root.app
        glyph: KG.back
        color: root.app.ui.scrimInk
        label: "Leave fullscreen"
        onClicked: root.app.setFullscreen(false)
      }
      Text {
        visible: root.full
        x: 56
        y: 8
        width: parent.width - 120
        height: 44
        verticalAlignment: Text.AlignVCenter
        text: root.item ? root.item.title : ""
        elide: Text.ElideRight
        color: root.app.ui.scrimInk
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
        font.weight: Font.Bold
      }
      IconButton {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        app: root.app
        glyph: KG.close
        color: root.app.ui.scrimInk
        label: "Stop"
        onClicked: root.app.stopPlaying()
      }

      // The three in the middle: back ten, play or pause, on ten.
      Row {
        anchors.centerIn: parent
        spacing: root.full ? 56 : 32
        RoundKey {
          anchors.verticalCenter: parent.verticalCenter
          glyph: G.back10
          big: false
          onPressed: { root.app.seekBy(-10000); root.poke() }
        }
        RoundKey {
          anchors.verticalCenter: parent.verticalCenter
          glyph: root.playing ? KG.pause : KG.play
          big: true
          visible: !root.busy
          onPressed: { root.app.togglePause(); root.poke() }
        }
        Spinner {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.busy
          running: visible
          app: root.app
          size: 48
        }
        RoundKey {
          anchors.verticalCenter: parent.verticalCenter
          glyph: G.forward10
          big: false
          onPressed: { root.app.seekBy(10000); root.poke() }
        }
      }

      // The line along the bottom, the clock, the quality and the corners.
      Item {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.rightMargin: 4
        height: 44

        Text {
          id: clockText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: L.clock(seeker.dragging ? seeker.value : root.media.position) + " / " + L.clock(root.media.duration)
          color: root.app.ui.scrimInk
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: Font.Bold
          font.features: ({ "tnum": 1 })
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.app.variants.length > 1
            text: root.app.variantLabel
            color: root.app.ui.scrimInk
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
            font.weight: Font.Bold
            leftPadding: 10
            rightPadding: 10
            topPadding: 12
            bottomPadding: 12
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.app.nextQuality(); root.poke() }
            }
          }
          IconButton {
            app: root.app
            glyph: root.full ? G.shrink : G.expand
            color: root.app.ui.scrimInk
            label: root.full ? "Leave fullscreen" : "Fullscreen"
            onClicked: { root.app.setFullscreen(!root.full); root.poke() }
          }
        }
      }

      // The timeline: a thin line, a thick finger's worth of target.
      Item {
        id: seeker
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bar.top
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        height: 32
        readonly property real total: Math.max(1, root.media.duration)
        property bool dragging: false
        property real value: 0
        readonly property real shown: dragging ? value : root.media.position
        readonly property real frac: Math.max(0, Math.min(1, shown / total))

        Rectangle {
          id: track
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: seeker.dragging ? 6 : 4
          color: root.app.ui.alpha(root.app.ui.scrimInk, 0.3)
          Rectangle {
            width: parent.width * (root.media.bufferProgress > 0 && root.media.bufferProgress < 1
              ? Math.min(1, seeker.frac + root.media.bufferProgress * 0.1) : seeker.frac)
            height: parent.height
            color: root.app.ui.alpha(root.app.ui.scrimInk, 0.35)
          }
          Rectangle {
            width: parent.width * seeker.frac
            height: parent.height
            color: root.app.ui.accent
          }
        }
        Rectangle {
          x: track.width * seeker.frac - width / 2
          anchors.verticalCenter: parent.verticalCenter
          width: seeker.dragging ? 20 : 14
          height: width
          radius: width / 2
          color: root.app.ui.accent
          border.width: 2
          border.color: root.app.ui.scrimInk
        }
        MouseArea {
          anchors.fill: parent
          anchors.topMargin: -8
          anchors.bottomMargin: -4
          preventStealing: true
          cursorShape: Qt.PointingHandCursor
          function at(mx) { return Math.max(0, Math.min(1, mx / width)) * seeker.total }
          onPressed: function (mouse) { seeker.dragging = true; seeker.value = at(mouse.x); root.poke() }
          onPositionChanged: function (mouse) { if (seeker.dragging) seeker.value = at(mouse.x) }
          onReleased: { root.app.seekTo(seeker.value); seeker.dragging = false; root.poke() }
          onCanceled: seeker.dragging = false
        }
      }
    }
  }

  readonly property bool landscape: {
    var r = out.sourceRect
    if (r && r.width > 0 && r.height > 0) return r.width >= r.height
    return !item || !item.height || item.width >= item.height
  }

  // A round key on the video: a disc because it floats over a picture, as a
  // player's keys do, not a box on the page.
  component RoundKey: Rectangle {
    id: key
    property string glyph: ""
    property bool big: false
    signal pressed()
    width: big ? 68 : 50
    height: width
    radius: width / 2
    color: keyMouse.pressed ? root.app.ui.alpha(root.app.ui.scrimStrong, 0.95) : root.app.ui.scrimStrong
    Icon {
      anchors.centerIn: parent
      app: root.app
      text: key.glyph
      size: key.big ? 36 : 24
      color: root.app.ui.scrimInk
    }
    MouseArea {
      id: keyMouse
      anchors.fill: parent
      anchors.margins: -6
      cursorShape: Qt.PointingHandCursor
      onClicked: key.pressed()
    }
  }
}
