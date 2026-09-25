import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// One movie or show in a grid or a shelf: the poster, marks for what is yours,
// the title, and the year with Trakt's rating.
Item {
  id: root
  property var app
  property var item: ({})
  property bool current: false
  property string badge: ""
  property string badgeGlyph: ""
  property string subtitle: ""
  property color ground: app.ui.bg
  signal activated()

  readonly property real posterHeight: Math.round(width * 1.5)
  readonly property bool listed: { app.library.rev; return app.library.inWatchlist(item) }
  readonly property int plays: { app.library.rev; return item.type === "movie" ? app.library.plays(item) : 0 }

  implicitHeight: posterHeight + 52
  Accessible.role: Accessible.Button
  Accessible.name: (item.title || "") + (item.year ? " (" + item.year + ")" : "")

  Item {
    id: frame
    width: parent.width
    height: root.posterHeight
    scale: mouse.pressed ? 0.97 : mouse.containsMouse ? 1.03 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Poster {
      anchors.fill: parent
      app: root.app
      source: root.item.poster || ""
      title: root.item.title || ""
      tint: root.item.tint || ""
      glyph: root.item.type === "show" ? G.tv : G.movie
      ground: root.ground
    }

    // Keyboard cursor.
    Rectangle {
      anchors.fill: parent
      anchors.margins: -3
      visible: root.current
      color: "transparent"
      radius: root.app.ui.radius + 3
      border.width: 2
      border.color: root.app.ui.accent
    }

    // Rank, or a figure with what it counts, top left.
    Rectangle {
      visible: root.badge !== ""
      x: 6
      y: 6
      height: 20
      width: Math.min(badgeRow.implicitWidth + 14, parent.width - 12)
      radius: 10
      color: Qt.rgba(0, 0, 0, 0.62)
      Row {
        id: badgeRow
        anchors.centerIn: parent
        spacing: 3
        Icon {
          visible: root.badgeGlyph !== ""
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          text: root.badgeGlyph
          size: 12
          width: 13
          color: "white"
        }
        Text {
          id: badgeText
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, root.width - 40)
          elide: Text.ElideRight
          text: root.badge
          color: "white"
          font.family: root.app.ui.font
          font.pixelSize: 11
          font.weight: Font.DemiBold
        }
      }
    }

    // Yours: on the watchlist, or seen.
    Row {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 6
      spacing: 4
      Rectangle {
        visible: root.plays > 0
        width: 22
        height: 22
        radius: 11
        color: root.app.ui.good
        Icon { anchors.centerIn: parent; app: root.app; text: G.check; size: 14; color: "white" }
      }
      Rectangle {
        visible: root.listed
        width: 22
        height: 22
        radius: 11
        color: root.app.ui.accent
        Icon { anchors.centerIn: parent; app: root.app; text: G.bookmarked; size: 13; color: root.app.onAccent }
      }
    }
  }

  Column {
    anchors.top: frame.bottom
    anchors.topMargin: 7
    width: parent.width
    spacing: 2
    Text {
      width: parent.width
      text: root.item.title || ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.weight: Font.DemiBold
      elide: Text.ElideRight
    }
    Row {
      width: parent.width
      spacing: 4
      Text {
        id: sub
        text: root.subtitle || Api.year(root.item.year) || (root.item.type === "show" ? "Show" : "Movie")
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width - (pct.visible ? pct.implicitWidth + 22 : 0))
      }
      Icon {
        visible: pct.visible
        anchors.verticalCenter: sub.verticalCenter
        app: root.app
        text: G.heart
        size: 11
        width: 12
        color: root.app.ui.heart
      }
      Text {
        id: pct
        visible: text !== ""
        text: Api.percent(root.item.rating)
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
