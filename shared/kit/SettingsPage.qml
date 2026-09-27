import QtQuick

// The settings screen: what the app is, then its sections, in a column no
// wider than reads well.
//
//   settings: Component {
//     SettingsPage {
//       app: root
//       blurb: "Notes and checklists"
//       SettingsSection { ... }
//       AppearanceSection { app: root }
//       LauncherSection { app: root }
//       KeysSection { app: root; keys: [["/", "Search"], ...] }
//     }
//   }
Flickable {
  id: root
  property var app
  // Under the name and version in the card at the top.
  property string blurb: ""
  default property alias content: body.data

  contentWidth: width
  contentHeight: body.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  Column {
    id: body
    x: root.app.compact ? 16 : 26
    y: 8
    width: Math.min(root.width - x * 2, 680)
    spacing: 26

    Rectangle {
      width: parent.width
      height: hero.implicitHeight + 40
      radius: root.app.ui.radius + 4
      color: root.app.ui.surface
      border.width: 1
      border.color: root.app.ui.divider

      Row {
        id: hero
        x: 20
        y: 20
        width: parent.width - 40
        spacing: 16
        Loader {
          id: heroMark
          active: root.app.mark !== null
          visible: active
          anchors.verticalCenter: parent.verticalCenter
          width: 56
          height: 56
          sourceComponent: root.app.mark
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - (heroMark.visible ? 72 : 0)
          spacing: 3
          Text {
            text: root.app.title + (root.app.version ? " " + root.app.version : "")
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.lg + 2
            font.weight: Font.Bold
          }
          Text {
            visible: root.blurb !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: root.blurb
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
        }
      }
    }
  }
}
