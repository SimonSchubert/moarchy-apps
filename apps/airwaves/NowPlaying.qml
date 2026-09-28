import QtQuick
import Quickshell
import "Api.mjs" as Api
import "Glyphs.js" as G

// The station on air, large: its picture, the song it says is playing, play
// and stop, volume, a sleep timer, and what the directory knows about it --
// each tag, the country and the language a way into more like it.
//
// Side by side when the window is wide, one column on a phone.
Item {
  id: root
  property var app

  readonly property var player: app.player
  readonly property var station: player.station || ({})
  readonly property bool wide: width >= 860
  readonly property real hue: station.hue !== undefined ? station.hue : 210
  readonly property bool favorite: { app.store.prefs; return app.store.isFavorite(station.id) }
  readonly property bool voted: app.voted[station.id] === true

  readonly property string statusText: {
    switch (player.status) {
    case "connecting": return "Connecting…"
    case "buffering": return "Buffering…"
    case "playing": return "Live"
    case "failed": return "Can't play"
    }
    return "Stopped"
  }

  function refresh(force) {}
  function scroll(dy) { flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy)) }

  // The station's colour, washing down from the top.
  Rectangle {
    anchors.fill: parent
    color: root.app.ui.bg
  }
  Rectangle {
    width: parent.width
    height: Math.min(parent.height, 560)
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.hsla(root.hue / 360, 0.55, root.app.ui.dark ? 0.3 : 0.8, 1) }
      GradientStop { position: 1.0; color: root.app.ui.bg }
    }
  }

  Item {
    id: header
    width: parent.width
    height: root.app.compact ? 56 : 64
    z: 2
    IconButton {
      id: backBtn
      x: 4
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      glyph: root.app.compact ? G.chevronDown : G.back
      label: "Back"
      onClicked: root.app.back()
    }
    Text {
      anchors.centerIn: parent
      text: "NOW PLAYING"
      color: root.app.alpha(root.app.ui.text, 0.7)
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.weight: Font.Bold
      font.letterSpacing: 1.6
    }
    IconButton {
      anchors.right: parent.right
      anchors.rightMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      visible: root.station.homepage !== ""
      app: root.app
      glyph: G.web
      label: "Open the station's website"
      onClicked: root.app.openLink(root.station.homepage)
    }
  }

  Flickable {
    id: flick
    anchors.top: header.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: layout.height + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Item {
      id: layout
      x: root.wide ? 40 : 20
      width: flick.width - x * 2
      height: root.wide ? Math.max(stage.height, details.height) : stage.height + 28 + details.height

      // ------------------------------------------------ the stage
      Column {
        id: stage
        width: root.wide ? Math.min(420, layout.width * 0.46) : layout.width
        spacing: 18

        Item {
          width: parent.width
          height: artBox.height + 8
          Rectangle {
            // A soft shadow: the art's own shape, darker, a little lower.
            anchors.horizontalCenter: artBox.horizontalCenter
            y: artBox.y + 10
            width: artBox.width - 16
            height: artBox.height - 4
            radius: art.radius
            color: Qt.hsla(root.hue / 360, 0.6, 0.15, root.app.ui.dark ? 0.55 : 0.28)
          }
          Item {
            id: artBox
            anchors.horizontalCenter: parent.horizontalCenter
            // Never so large that the controls fall below the fold.
            width: Math.min(parent.width - (root.wide ? 0 : 40), root.wide ? 400 : 320, flick.height * 0.42)
            height: width
            Art {
              id: art
              anchors.fill: parent
              app: root.app
              station: root.station
              radius: 24
              letterScale: 0.3
            }
          }
        }

        // Live, or what it is doing instead.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 8
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: livePill.implicitWidth + 20
            height: 24
            radius: 12
            color: root.player.status === "playing" ? root.app.alpha(root.app.ui.live, 0.16)
              : root.player.status === "failed" ? root.app.alpha(root.app.ui.down, 0.16) : root.app.ui.surfaceHigh
            Row {
              id: livePill
              anchors.centerIn: parent
              spacing: 6
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 4
                visible: root.player.status === "playing"
                color: root.app.ui.live
                SequentialAnimation on opacity {
                  running: root.player.status === "playing" && root.visible && root.app.opened && !root.app.offline
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                  NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                }
              }
              Spinner {
                anchors.verticalCenter: parent.verticalCenter
                app: root.app
                size: 12
                running: root.player.status === "connecting" || root.player.status === "buffering"
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.statusText.toUpperCase()
                color: root.player.status === "playing" ? root.app.ui.live
                  : root.player.status === "failed" ? root.app.ui.down : root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 1
              }
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: text !== ""
            text: Api.quality({ codec: root.player.codec || root.station.codec, bitrate: root.station.bitrate })
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
        }

        Column {
          width: parent.width
          spacing: 8
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.station.name || ""
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xl
            font.weight: Font.Bold
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
          // The song, when the station says; where it is, when not.
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, parent.width)
            spacing: 4
            Icon {
              visible: root.player.song !== ""
              anchors.verticalCenter: parent.verticalCenter
              app: root.app
              text: G.note
              size: 16
              color: root.app.ui.accent
            }
            Text {
              width: Math.min(implicitWidth, stage.width - 30)
              anchors.verticalCenter: parent.verticalCenter
              text: root.player.failure || root.player.song || Api.place(root.station) || Api.subtitle(root.station)
              color: root.player.failure ? root.app.ui.down : root.player.song ? root.app.ui.text : root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md + 1
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }

        // Star, play or stop, vote.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 28
          IconButton {
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            glyph: root.favorite ? G.star : G.starOutline
            color: root.favorite ? root.app.ui.star : root.app.ui.text
            size: 24
            label: root.favorite ? "Remove from favourites" : "Add to favourites"
            onClicked: root.app.toggleFavorite(root.station)
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 76
            height: 76
            radius: 38
            color: playMouse.pressed ? Qt.darker(root.app.ui.accent, 1.15) : root.app.ui.accent
            scale: playMouse.pressed ? 0.95 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
            Accessible.role: Accessible.Button
            Accessible.name: root.player.active ? "Stop" : "Play"
            Icon {
              anchors.centerIn: parent
              app: root.app
              text: root.player.active ? G.stop : G.play
              size: 36
              color: root.app.onAccent
            }
            MouseArea {
              id: playMouse
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.player.toggle()
            }
          }
          IconButton {
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            glyph: root.voted ? G.voted : G.vote
            color: root.voted ? root.app.ui.accent : root.app.ui.text
            size: 24
            label: "Vote for this station"
            onClicked: root.app.vote(root.station)
          }
        }

        // Volume.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(parent.width, 340)
          spacing: 4
          IconButton {
            anchors.verticalCenter: parent.verticalCenter
            app: root.app
            glyph: root.player.muted || root.player.volume === 0 ? G.volumeOff
              : root.player.volume < 34 ? G.volumeLow : root.player.volume < 67 ? G.volumeMedium : G.volumeHigh
            label: root.player.muted ? "Unmute" : "Mute"
            size: 20
            color: root.app.ui.muted
            onClicked: root.player.setMuted(!root.player.muted)
          }
          Slider {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 44 - 44
            app: root.app
            value: root.player.muted ? 0 : root.player.volume
            onMoved: function (v) { root.player.setVolume(v) }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            horizontalAlignment: Text.AlignRight
            text: root.player.muted ? "Muted" : root.player.volume
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
            font.features: ({ "tnum": 1 })
          }
        }

        // Sleep timer.
        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 8
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            Icon {
              anchors.verticalCenter: parent.verticalCenter
              app: root.app
              text: G.sleep
              size: 16
              color: root.app.ui.muted
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.player.sleepAt > 0
                ? "Stops in " + Api.clock(root.player.sleepAt - root.app.clock)
                : "Sleep timer"
              color: root.player.sleepAt > 0 ? root.app.ui.accent : root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
            }
          }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            Repeater {
              model: [0, 15, 30, 60, 90]
              delegate: Chip {
                required property int modelData
                app: root.app
                hpad: 20
                text: modelData === 0 ? "Off" : modelData + " min"
                selected: modelData === 0 ? root.player.sleepAt === 0 : root.app.sleepChoice === modelData && root.player.sleepAt > 0
                onClicked: root.app.sleep(modelData)
              }
            }
          }
        }

        Button {
          visible: root.player.failure !== ""
          anchors.horizontalCenter: parent.horizontalCenter
          app: root.app
          glyph: G.refresh
          text: "Try again"
          onClicked: root.player.play(root.station)
        }
      }

      // ------------------------------------------------ about it
      Rectangle {
        id: details
        x: root.wide ? stage.width + 40 : 0
        y: root.wide ? 0 : stage.height + 28
        width: root.wide ? layout.width - stage.width - 40 : layout.width
        height: about.implicitHeight + 40
        radius: root.app.ui.radius + 6
        color: root.app.ui.surface
        border.width: 1
        border.color: root.app.ui.divider

        Column {
          id: about
          x: 20
          y: 20
          width: parent.width - 40
          spacing: 16

          Text {
            text: "About this station"
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.lg
            font.weight: Font.Bold
          }

          Flow {
            visible: (root.station.tags || []).length > 0
            width: parent.width
            spacing: 6
            Repeater {
              model: root.station.tags || []
              delegate: Chip {
                required property string modelData
                app: root.app
                hpad: 20
                glyph: G.tag
                text: modelData
                onClicked: root.app.openList({ facet: "tag", value: modelData, label: modelData })
              }
            }
          }

          Column {
            width: parent.width
            spacing: 0
            Repeater {
              model: {
                var s = root.station
                var rows = []
                if (s.country) rows.push({ g: G.marker, k: "Location", v: Api.place(s), go: s.cc ? { facet: "country", value: s.cc, label: s.country } : null })
                if (s.language) rows.push({ g: G.language, k: "Language", v: s.language,
                  go: { facet: "language", value: s.language.split(",")[0].trim().toLowerCase(), label: s.language.split(",")[0].trim() } })
                var qual = Api.quality({ codec: root.player.codec || s.codec, bitrate: s.bitrate })
                if (qual || s.hls) rows.push({ g: G.equalizer, k: "Stream", v: (qual || "") + (s.hls ? (qual ? " · " : "") + "HLS" : ""), go: null })
                rows.push({ g: G.vote, k: "Votes", v: Api.group(s.votes || 0), go: null })
                // The directory counts listens over the last day, and the
                // change against the day before.
                rows.push({ g: G.trending, k: "Listens", v: Api.group(s.clicks || 0) + " today"
                  + (s.trend > 0 ? " · up " + Api.group(s.trend) : s.trend < 0 ? " · down " + Api.group(-s.trend) : ""), go: null })
                return rows
              }
              delegate: Rectangle {
                id: factRow
                required property var modelData
                width: about.width
                height: 48
                radius: root.app.ui.radius
                color: factMouse.containsMouse && factRow.modelData.go ? root.app.ui.hover : "transparent"
                Icon {
                  id: factIcon
                  anchors.verticalCenter: parent.verticalCenter
                  app: root.app
                  text: factRow.modelData.g
                  size: 17
                  color: root.app.ui.muted
                }
                Text {
                  id: factKey
                  anchors.left: factIcon.right
                  anchors.leftMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  width: 88
                  text: factRow.modelData.k
                  color: root.app.ui.muted
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.sm
                }
                Text {
                  anchors.left: factKey.right
                  anchors.right: factChev.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: factRow.modelData.v
                  color: root.app.ui.text
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.sm
                  font.weight: Font.DemiBold
                  elide: Text.ElideRight
                }
                Icon {
                  id: factChev
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  visible: factRow.modelData.go !== null
                  width: visible ? implicitWidth : 0
                  app: root.app
                  text: G.chevronRight
                  size: 16
                  color: root.app.ui.muted
                }
                Rectangle {
                  anchors.bottom: parent.bottom
                  width: parent.width
                  height: 1
                  color: root.app.ui.divider
                }
                MouseArea {
                  id: factMouse
                  anchors.fill: parent
                  enabled: factRow.modelData.go !== null
                  hoverEnabled: !root.app.compact
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.app.openList(factRow.modelData.go)
                }
              }
            }
          }

          Flow {
            width: parent.width
            spacing: 8
            Button {
              visible: root.station.homepage !== ""
              app: root.app
              glyph: G.web
              text: "Website"
              onClicked: root.app.openLink(root.station.homepage)
            }
            Button {
              app: root.app
              glyph: G.link
              text: "Copy stream link"
              onClicked: { Quickshell.clipboardText = root.station.stream; root.app.toast("Stream link copied") }
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: "Listed in the community directory at radio-browser.info. Airwaves isn't affiliated with this station."
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
        }
      }
    }
  }
}
