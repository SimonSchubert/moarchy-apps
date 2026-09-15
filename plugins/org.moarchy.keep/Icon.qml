// A symbolic SVG, recoloured to the surface ink.
//
// Quickshell.iconPath() asks the icon theme (Yaru-magenta here) at the
// control's 44px slot and comes back empty. GTK Keep finds the same names
// through Adwaita's fallback chain. We load Adwaita's file directly.
//
// Those SVGs ship with fill="#2e3436". libadwaita tints them; Image does
// not, so on a dark grid they are invisible. ColorOverlay is that tint.
import QtQuick
import Qt5Compat.GraphicalEffects

Item {
  id: root
  property var names: []
  property int size: 22
  property int slot: 44
  property color color: "#ffffff"

  width: slot
  height: slot

  readonly property var files: ({
    "view-list-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-list-symbolic.svg",
    "view-grid-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-grid-symbolic.svg",
    "view-app-grid-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-app-grid-symbolic.svg",
    "go-previous-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg",
    "pan-start-symbolic": "/usr/share/icons/Adwaita/symbolic/ui/pan-start-symbolic.svg",
    "pan-down-symbolic": "/usr/share/icons/Adwaita/symbolic/ui/pan-down-symbolic.svg",
    "pan-end-symbolic": "/usr/share/icons/Adwaita/symbolic/ui/pan-end-symbolic.svg",
    "checkbox-checked-symbolic": "/usr/share/icons/Adwaita/symbolic/ui/checkbox-checked-symbolic.svg",
    "system-search-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/system-search-symbolic.svg",
    "view-more-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-more-symbolic.svg",
    "open-menu-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/open-menu-symbolic.svg",
    "view-pin-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-pin-symbolic.svg",
    "starred-symbolic": "/usr/share/icons/Adwaita/symbolic/status/starred-symbolic.svg",
    "color-select-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/color-select-symbolic.svg",
    "user-trash-symbolic": "/usr/share/icons/Adwaita/symbolic/places/user-trash-symbolic.svg",
    "list-add-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/list-add-symbolic.svg",
    "window-close-symbolic": "/usr/share/icons/Adwaita/symbolic/ui/window-close-symbolic.svg",
    "action-unavailable-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/action-unavailable-symbolic.svg",
    "object-select-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/object-select-symbolic.svg"
  })

  readonly property string source: {
    var list = root.names || []
    for (var i = 0; i < list.length; i++) {
      var path = root.files[String(list[i])]
      if (path) return "file://" + path
    }
    return ""
  }

  Image {
    id: img
    anchors.centerIn: parent
    width: root.size
    height: root.size
    sourceSize.width: root.size
    sourceSize.height: root.size
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: true
    source: root.source
    visible: false
  }

  ColorOverlay {
    anchors.fill: img
    source: img
    color: root.color
    visible: img.status === Image.Ready
  }
}
