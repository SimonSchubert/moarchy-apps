import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Calc.js" as Calc

// The tape: every sum `=` has answered, newest at the bottom, the way a till
// roll reads. Tapping a line puts its answer back on the display, to carry on
// from.
Item {
  id: root
  property var app
  property var tape: []
  property bool titled: true
  signal picked(string answer)
  signal cleared()

  SectionTitle {
    id: heading
    app: root.app
    visible: root.titled
    text: "Tape"
    note: root.tape.length === 1 ? "1 sum" : root.tape.length + " sums"
    height: clear.height
  }
  Button {
    id: clear
    anchors.right: parent.right
    visible: root.tape.length > 0
    app: root.app
    text: "Clear"
    glyph: KG.remove
    onClicked: root.cleared()
  }

  ListView {
    id: list
    anchors.top: heading.bottom
    anchors.topMargin: 10
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    spacing: 4
    model: root.tape
    boundsBehavior: Flickable.StopAtBounds
    // Newest at the bottom, and the bottom is where the list opens.
    verticalLayoutDirection: ListView.BottomToTop
    onCountChanged: positionViewAtBeginning()

    delegate: Rectangle {
      id: line
      required property int index
      // The model reads bottom to top, so the newest is index 0.
      readonly property var item: root.tape[root.tape.length - 1 - index]
      width: list.width
      height: col.implicitHeight + 16
      radius: root.app.ui.radius
      color: tap.pressed ? root.app.ui.pressed : tap.containsMouse ? root.app.ui.hover : root.app.ui.surface
      border.width: 1
      border.color: root.app.ui.line

      Column {
        id: col
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        width: parent.width - 24
        spacing: 2
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideLeft
          text: line.item ? Calc.pretty(line.item.sum) : ""
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.features: ({ "tnum": 1 })
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideLeft
          text: line.item ? "= " + Calc.pretty(line.item.answer) : ""
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.lg
          font.weight: Font.Bold
          font.features: ({ "tnum": 1 })
        }
      }

      MouseArea {
        id: tap
        anchors.fill: parent
        hoverEnabled: !root.app.compact
        cursorShape: Qt.PointingHandCursor
        onClicked: if (line.item) root.picked(line.item.answer)
      }
    }
  }

  EmptyState {
    anchors.centerIn: list
    visible: root.tape.length === 0
    app: root.app
    glyph: KG.history
    title: "Nothing on the tape"
    text: "Every sum answered with = is written here. Tap one to carry on from it."
  }
}
