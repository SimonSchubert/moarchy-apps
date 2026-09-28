import QtQuick

// To, Cc, Bcc or Subject, in front of its field and level with it.
Text {
  property var app
  width: 58
  height: app.compact ? 44 : 38
  verticalAlignment: Text.AlignVCenter
  color: app.ui.muted
  font.family: app.ui.font
  font.pixelSize: app.ui.fs.xs
  font.weight: Font.Bold
  font.capitalization: Font.AllUppercase
  font.letterSpacing: app.ui.tracking
  elide: Text.ElideRight
}
