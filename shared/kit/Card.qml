import QtQuick

// A box with a heading. The heading is a glyph, a title and an optional
// figure on the right; the body is whatever is put inside, stacked.
//
// `clickable` makes the whole card a way into its page: on the overview a
// card is a summary, and the page it summarises is one tap away.
Rectangle {
  id: root
  property var app
  property string title: ""
  property string glyph: ""
  property color glyphColor: app.ui.muted
  property string trailing: ""
  property color trailingColor: app.ui.muted
  property bool clickable: false
  property int pad: app.compact ? 14 : 18
  default property alias content: body.data
  signal clicked()

  implicitHeight: body.y + body.implicitHeight + pad
  radius: app.ui.radius
  color: clickable && mouse.pressed ? Qt.tint(app.ui.surface, app.ui.pressed)
    : clickable && mouse.containsMouse ? Qt.tint(app.ui.surface, app.ui.hover) : app.ui.surface
  border.width: 1
  border.color: app.ui.line

  // Under the body, so a row inside the card that can be pressed is pressed
  // rather than the card.
  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.clickable
    hoverEnabled: root.clickable && !root.app.compact
    cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  Row {
    id: head
    visible: root.title !== ""
    x: root.pad
    y: root.pad - 2
    width: parent.width - root.pad * 2
    height: visible ? 24 : 0
    spacing: 6
    Icon {
      visible: root.glyph !== ""
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      text: root.glyph
      size: 15
      width: 18
      color: root.glyphColor
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - (root.glyph !== "" ? 24 : 0) - trail.implicitWidth - 6
      text: root.title
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
      font.weight: Font.Bold
      font.capitalization: Font.AllUppercase
      font.letterSpacing: root.app.ui.tracking
      elide: Text.ElideRight
    }
  }
  Text {
    id: trail
    anchors.right: parent.right
    anchors.rightMargin: root.pad
    anchors.verticalCenter: head.verticalCenter
    visible: root.title !== "" && root.trailing !== ""
    text: root.trailing
    color: root.trailingColor
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
    font.features: ({ "tnum": 1 })
  }

  Column {
    id: body
    x: root.pad
    y: head.visible ? head.y + head.height + 10 : root.pad
    width: parent.width - root.pad * 2
    spacing: 10
  }
}
