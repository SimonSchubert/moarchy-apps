import QtQuick

// The minutes a change leaves you. Red when they are fewer than the walk
// needs plus a breath, amber when it will be a brisk one.
Rectangle {
  id: root
  property var app
  property var change: null

  readonly property int spare: change ? change.minutes - change.walk : 99
  readonly property color tone: spare < 2 ? app.ui.late : spare < 4 ? app.ui.warn : app.ui.muted

  implicitHeight: 22
  implicitWidth: label.implicitWidth + 14
  radius: 11
  color: spare < 2 ? app.ui.lateSoft : spare < 4 ? app.ui.warnSoft : app.ui.surfaceHigh

  Text {
    id: label
    anchors.centerIn: parent
    text: !root.change ? "" : (root.spare < 2 ? "Tight change · " : "Change · ") + Math.max(0, root.change.minutes) + " min"
    color: root.tone === root.app.ui.muted ? root.app.ui.text : root.tone
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
    font.weight: Font.DemiBold
  }
}
