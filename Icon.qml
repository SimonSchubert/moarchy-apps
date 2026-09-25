import QtQuick

// One Nerd Font glyph, centred in a square slot so a column of them lines up.
Text {
  property var app
  property int size: 18
  width: Math.round(size * 1.4)
  height: width
  font.family: "JetBrainsMono Nerd Font"
  font.pixelSize: size
  color: app ? app.ui.text : "white"
  horizontalAlignment: Text.AlignHCenter
  verticalAlignment: Text.AlignVCenter
}
