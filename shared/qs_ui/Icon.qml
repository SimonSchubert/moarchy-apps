// A symbolic SVG, recoloured to the surface ink.
//
// Quickshell.iconPath() asks the icon theme (Yaru-magenta here) at the
// control's 44px slot and comes back empty. GTK finds the same names
// through Adwaita's fallback chain. We load Adwaita's file directly, and
// keep the themed lookup as the fallback for systems that are not our image.
//
// Those SVGs ship with fill="#2e3436". libadwaita tints them; Image does
// not, so on a dark grid they are invisible. ColorOverlay is that tint.
import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects

Item {
  id: root
  property var names: []
  property int size: 18  // Metrics.ICON_INK; Adwaita fills the canvas, MD does not
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
    "non-starred-symbolic": "/usr/share/icons/Adwaita/symbolic/status/non-starred-symbolic.svg",
    "color-select-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/color-select-symbolic.svg",
    "user-trash-symbolic": "/usr/share/icons/Adwaita/symbolic/places/user-trash-symbolic.svg",
    "list-add-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/list-add-symbolic.svg",
    "window-close-symbolic": "/usr/share/icons/Adwaita/symbolic/ui/window-close-symbolic.svg",
    "action-unavailable-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/action-unavailable-symbolic.svg",
    "object-select-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/object-select-symbolic.svg",
    "view-refresh-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/view-refresh-symbolic.svg",
    "edit-clear-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/edit-clear-symbolic.svg",
    "edit-find-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/edit-find-symbolic.svg",
    "computer-symbolic": "/usr/share/icons/Adwaita/symbolic/devices/computer-symbolic.svg",
    "drive-harddisk-symbolic": "/usr/share/icons/Adwaita/symbolic/devices/drive-harddisk-symbolic.svg",
    "network-wireless-symbolic": "/usr/share/icons/Adwaita/symbolic/devices/network-wireless-symbolic.svg",
    "system-run-symbolic": "/usr/share/icons/Adwaita/symbolic/actions/system-run-symbolic.svg"
  })

  // Which candidate we are on. An Adwaita install somewhere other than
  // /usr/share/icons, or a system with a different theme entirely, only shows
  // up as an Image that failed to load, so failing is how we walk the list.
  property int attempt: 0
  onNamesChanged: root.attempt = 0

  function candidate(n) {
    var list = root.names || []
    var i
    for (i = 0; i < list.length; i++) {
      var path = root.files[String(list[i])]
      if (!path) continue
      if (n === 0) return "file://" + path
      n--
    }
    // The themed lookup is the portable half, and it is second because it is
    // the expensive one: Quickshell.iconPath() walks the icon theme, which on
    // our image misses anyway. Nothing pays for it until the paths above fail.
    for (i = 0; i < list.length; i++) {
      var themed = Quickshell.iconPath(String(list[i]), true)
      if (!themed) continue
      if (n === 0) return themed
      n--
    }
    return ""
  }

  readonly property string source: root.candidate(root.attempt)

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
    onStatusChanged: {
      if (status !== Image.Error) return
      if (root.candidate(root.attempt + 1) !== "") root.attempt++
    }
  }

  ColorOverlay {
    anchors.fill: img
    source: img
    color: root.color
    visible: img.status === Image.Ready
  }
}
