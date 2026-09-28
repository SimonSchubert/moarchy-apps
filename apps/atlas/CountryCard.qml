import QtQuick
import "kit"
import "Countries.js" as C

// One country in the grid: its flag, its name, and under it the capital -- or
// the figure the grid is sorted by, when it is sorted by one.
Rectangle {
  id: root
  property var app
  property var country: null
  property string sort: "name"
  property bool selected: false
  property bool current: false
  signal opened()

  radius: app.ui.radius
  color: selected ? app.ui.selected : mouse.pressed ? Qt.tint(app.ui.surface, app.ui.pressed)
    : mouse.containsMouse ? Qt.tint(app.ui.surface, app.ui.hover) : app.ui.surface
  border.width: selected || (current && !app.compact) ? 2 : 1
  border.color: selected || (current && !app.compact) ? app.ui.accent : app.ui.line
  Accessible.role: Accessible.Button
  Accessible.name: country ? country.name : ""

  readonly property int pad: app.compact ? 10 : 12

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.opened()
  }

  Rectangle {
    id: stage
    x: root.pad
    y: root.pad
    width: parent.width - root.pad * 2
    height: Math.round(width * 0.62)
    color: root.app.ui.well
    radius: root.app.ui.radius > 0 ? 3 : 0
    Flag {
      anchors.fill: parent
      anchors.margins: root.app.compact ? 10 : 14
      app: root.app
      code: root.country ? root.country.code : ""
    }
  }

  Column {
    anchors.top: stage.bottom
    anchors.topMargin: 9
    x: root.pad
    width: parent.width - root.pad * 2
    spacing: 2
    Text {
      width: parent.width
      text: root.country ? root.country.name : ""
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.Bold
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      text: !root.country ? ""
        : root.sort === "population" ? C.people(root.country.population)
        : root.sort === "area" ? C.areaText(root.country.area)
        : C.line(root.country)
      color: root.sort === "name" ? root.app.ui.muted : root.app.ui.accent
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm - 1
      font.features: ({ "tnum": 1 })
      elide: Text.ElideRight
    }
  }
}
