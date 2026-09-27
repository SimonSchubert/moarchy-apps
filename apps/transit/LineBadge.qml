import QtQuick
import "Api.mjs" as Api

// A line as the signs at the stop show it: its own colour, its name, and the
// shape of its kind -- a pill for a bus, a block for a train.
Rectangle {
  id: root
  property var app
  property var leg: null
  property bool glyph: true
  property int size: 22
  property bool muted: false

  readonly property string label: leg ? (leg.line || Api.modeLabel(leg.mode)) : ""
  readonly property bool round: leg && (leg.mode === "BUS" || leg.mode === "COACH" || leg.mode === "TRAM")

  implicitHeight: size
  implicitWidth: Math.max(size + 6, row.implicitWidth + (round ? 16 : 12))
  radius: round ? height / 2 : Math.max(3, Math.round(size * 0.22))
  color: app.lineFill(leg)
  opacity: muted ? 0.45 : 1
  Accessible.role: Accessible.StaticText
  Accessible.name: (leg ? Api.modeLabel(leg.mode) + " " : "") + label

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 3
    Icon {
      visible: root.glyph
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      text: root.leg ? Api.modeGlyph(root.leg.mode) : ""
      size: Math.round(root.size * 0.58)
      width: Math.round(root.size * 0.7)
      color: root.app.lineOn(root.leg)
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      color: root.app.lineOn(root.leg)
      font.family: root.app.ui.font
      font.pixelSize: Math.round(root.size * 0.56)
      font.weight: Font.Bold
      font.features: ({ "tnum": 1 })
    }
  }
}
