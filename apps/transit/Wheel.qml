import QtQuick

// A column of values that snaps its middle row into the band behind it.
ListView {
  id: root
  property var app
  property int rows: 0
  property var format: function (i) { return "" + i }
  signal picked(int index)

  readonly property int rowH: 44
  model: rows
  clip: true
  snapMode: ListView.SnapToItem
  highlightRangeMode: ListView.StrictlyEnforceRange
  preferredHighlightBegin: height / 2 - rowH / 2
  preferredHighlightEnd: height / 2 + rowH / 2
  highlightMoveDuration: 120
  boundsBehavior: Flickable.StopAtBounds
  onCurrentIndexChanged: picked(currentIndex)

  delegate: Item {
    required property int index
    width: root.width
    height: root.rowH
    Text {
      anchors.centerIn: parent
      text: root.format(parent.index)
      color: root.currentIndex === parent.index ? root.app.ui.text : root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.currentIndex === parent.index ? 22 : 17
      font.weight: root.currentIndex === parent.index ? Font.Bold : Font.Normal
      font.features: ({ "tnum": 1 })
    }
    MouseArea { anchors.fill: parent; onClicked: root.currentIndex = parent.index }
  }
}
