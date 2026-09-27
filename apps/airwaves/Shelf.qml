import QtQuick

// A titled row of stations that scrolls sideways, with a way to see all of
// them. While it loads it shows the shape of what is coming, so the screen
// does not jump when it arrives.
Column {
  id: root
  property var app
  property string title: ""
  property string note: ""
  property var items: []
  property bool loading: false
  property int pad: 16
  signal seeAll()

  spacing: 12
  visible: items.length > 0 || loading

  SectionTitle {
    width: parent.width
    app: root.app
    pad: root.pad
    title: root.title
    note: root.note
    action: "See all"
    onTriggered: root.seeAll()
  }

  ListView {
    width: parent.width
    height: (root.app.compact ? 124 : 150) + 50
    orientation: ListView.Horizontal
    spacing: root.app.compact ? 12 : 18
    leftMargin: root.pad
    rightMargin: root.pad
    onLeftMarginChanged: contentX = -leftMargin
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: 400
    model: keyed.count ? keyed : root.loading ? 6 : 0
    delegate: keyed.count ? card : ghost
  }

  Keyed { id: keyed; items: root.items }

  Component {
    id: card
    StationCard {
      required property string key
      width: root.app.compact ? 124 : 150
      app: root.app
      station: keyed.at(key)
      onActivated: root.app.play(station)
    }
  }

  Component {
    id: ghost
    Column {
      spacing: 10
      Rectangle {
        width: root.app.compact ? 124 : 150
        height: width
        radius: root.app.ui.radius + 6
        color: root.app.ui.surfaceHigh
      }
      Rectangle { width: 90; height: 10; radius: 5; color: root.app.ui.surfaceHigh }
      Rectangle { width: 60; height: 8; radius: 4; color: root.app.ui.surface }
    }
  }
}
