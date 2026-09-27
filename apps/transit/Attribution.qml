import QtQuick

// Transitous asks every app that uses it to link to the sources of its data,
// and OpenStreetMap to be credited for the maps and addresses underneath.
Text {
  property var app
  horizontalAlignment: Text.AlignHCenter
  wrapMode: Text.Wrap
  textFormat: Text.StyledText
  linkColor: app.ui.accent
  text: "Routing by <a href=\"https://transitous.org\">Transitous</a> · timetables from "
    + "<a href=\"https://transitous.org/sources/\">these sources</a><br>"
    + "Map data © <a href=\"https://www.openstreetmap.org/copyright\">OpenStreetMap contributors</a>"
  color: app.ui.muted
  font.family: app.ui.font
  font.pixelSize: app.ui.fs.xs
  lineHeight: 1.3
  leftPadding: 20
  rightPadding: 20
  onLinkActivated: function (link) { Qt.openUrlExternally(link) }
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
  }
}
