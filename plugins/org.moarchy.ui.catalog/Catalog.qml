// Review surface for shared/qs_ui. Not an app: a window that puts every
// chrome piece on screen so a theme change and a thumb can both judge it.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "org.moarchy.ui.catalog"
  readonly property bool opened: catalogWindow.visible
  readonly property var appWindow: catalogWindow

  property string returnTo: ""
  // `colours` and not `palette`: QQuickItem already has a `palette`, and
  // shadowing it makes a binding resolve to whichever the compiler picked --
  // The property-override warning names it, and it is the one warning here
  // that could silently draw the wrong thing. (A comment must not open with
  // the linter's own name: it reads the rest of the line as a directive.)
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY
  Component.onCompleted: root.bodySize = Metrics.shellBody(root)
  property bool listed: true
  property bool boxed: false
  property bool menuOpen: false
  property bool spinning: false
  property string lastAction: ""
  property int tab: 0
  property string query: ""
  property string mission: ""
  property string both: "Starship"
  property string tabLabel: "Upcoming"

  readonly property color surface: colours.surface
  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
  readonly property color line: colours.line
  readonly property color accent: colours.accent

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
    } catch (e) {}
    catalogWindow.show()
  }

  function close() {}

  function dismiss() {
    catalogWindow.hide()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  Timer {
    id: spinDemo
    interval: 2500
    onTriggered: root.spinning = false
  }

  Chrome.ThemeFile { id: themeFile }

  Chrome.AppWindow {
    id: catalogWindow
    shell: root.shell
    appName: "Chrome"
    pluginId: root.pluginId
    color: root.background

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true
      Keys.onEscapePressed: {
        if (root.menuOpen) { root.menuOpen = false; return }
        root.dismiss()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 8
          title: "Chrome"
          foreground: root.textOnSurface
          bodySize: root.bodySize
          leading: Chrome.BackButton {
            color: root.textOnSurface
            onClicked: root.dismiss()
          }
          trailing: Row {
            Chrome.IconButton {
              color: root.textOnSurface
              names: ["view-refresh-symbolic"]
              tooltip: "Refresh"
              spinning: root.spinning
              onClicked: {
                root.spinning = true
                spinDemo.restart()
              }
            }
            Chrome.IconButton {
              color: root.textOnSurface
              names: ["open-menu-symbolic", "view-more-symbolic"]
              tooltip: "Menu"
              onClicked: root.menuOpen = !root.menuOpen
            }
          }
        }

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 8
          foreground: root.textOnSurface
          bodySize: root.bodySize
          center: Chrome.TextField {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            leadingNames: ["system-search-symbolic"]
            trailingNames: ["edit-clear-symbolic"]
            trailingClickable: true
            placeholderText: "Search in the bar"
            foreground: root.textOnSurface
            accent: root.accent
            iconColor: root.dim
            bodySize: root.bodySize
            text: root.query
            onTrailingClicked: root.query = ""
            onTextChanged: root.query = text
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          Flickable {
            id: flick
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: col.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: col
              width: flick.width
              leftPadding: 16
              rightPadding: 16
              topPadding: 12
              bottomPadding: Metrics.FAB + Metrics.BOTTOM_NAV + 24
              spacing: 16

              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                role: "overline"
                text: "TYPE"
                color: root.dim
                bodySize: root.bodySize
              }
              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                role: "title"
                text: "Title"
                color: root.textOnSurface
                bodySize: root.bodySize
              }
              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                role: "subtitle"
                text: "Subtitle"
                color: root.textOnSurface
                bodySize: root.bodySize
              }
              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                role: "body"
                text: "Body. The same Adwaita Sans and body size the shell uses."
                color: root.textOnSurface
                bodySize: root.bodySize
              }
              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                role: "caption"
                text: "Caption, for timestamps and secondary facts."
                color: root.dim
                bodySize: root.bodySize
              }

              Rectangle {
                width: parent.width - parent.leftPadding - parent.rightPadding
                height: 1
                color: root.line
              }

              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                role: "overline"
                text: "FIELDS"
                color: root.dim
                bodySize: root.bodySize
              }
              Chrome.TextField {
                width: parent.width - parent.leftPadding - parent.rightPadding
                placeholderText: "Plain"
                bodySize: root.bodySize
                foreground: root.textOnSurface
                accent: root.accent
                color: root.surface
              }
              Chrome.TextField {
                width: parent.width - parent.leftPadding - parent.rightPadding
                leadingNames: ["system-search-symbolic"]
                placeholderText: "Mission, vehicle, pad"
                bodySize: root.bodySize
                foreground: root.textOnSurface
                accent: root.accent
                iconColor: root.dim
                color: root.surface
                text: root.mission
                onTextChanged: root.mission = text
              }
              Chrome.TextField {
                id: trailingField
                width: parent.width - parent.leftPadding - parent.rightPadding
                trailingNames: ["edit-clear-symbolic"]
                trailingClickable: true
                placeholderText: "Trailing clear"
                bodySize: root.bodySize
                foreground: root.textOnSurface
                accent: root.accent
                iconColor: root.dim
                color: root.surface
                onTrailingClicked: trailingField.text = ""
              }
              Chrome.TextField {
                width: parent.width - parent.leftPadding - parent.rightPadding
                leadingNames: ["starred-symbolic"]
                trailingNames: ["edit-clear-symbolic"]
                trailingClickable: true
                placeholderText: "Both icons"
                bodySize: root.bodySize
                foreground: root.textOnSurface
                accent: root.accent
                iconColor: root.dim
                color: root.surface
                text: root.both
                onTrailingClicked: root.both = ""
                onTextChanged: root.both = text
              }

              Rectangle {
                width: parent.width - parent.leftPadding - parent.rightPadding
                height: 1
                color: root.line
              }

              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                role: "overline"
                text: "BUTTONS"
                color: root.dim
                bodySize: root.bodySize
              }
              Row {
                spacing: 8
                Chrome.BackButton {
                  color: root.textOnSurface
                }
                Chrome.IconButton {
                  color: root.textOnSurface
                  names: ["view-grid-symbolic", "view-app-grid-symbolic"]
                  tooltip: "Grid"
                }
                Chrome.IconButton {
                  color: root.textOnSurface
                  names: ["view-list-symbolic"]
                  tooltip: "List"
                }
                Chrome.IconButton {
                  color: root.accent
                  names: ["starred-symbolic"]
                  tooltip: "Star"
                }
              }

              Rectangle {
                width: parent.width - parent.leftPadding - parent.rightPadding
                height: 1
                color: root.line
              }

              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                role: "overline"
                text: "CHECKS"
                color: root.dim
                bodySize: root.bodySize
              }
              Chrome.Check {
                checked: root.listed
                text: root.listed ? "On a list — tap the label" : "Off the list — tap the label"
                foreground: root.textOnSurface
                tickColor: root.colours.dark ? "#ffffff" : root.background
                accent: root.accent
                dim: root.dim
                bodySize: root.bodySize
                onToggled: function (on) { root.listed = on }
              }
              Chrome.Check {
                checked: root.boxed
                interactive: false
                text: "Display only"
                foreground: root.textOnSurface
                tickColor: root.colours.dark ? "#ffffff" : root.background
                accent: root.accent
                dim: root.dim
                bodySize: root.bodySize
              }

              Rectangle {
                width: parent.width - parent.leftPadding - parent.rightPadding
                height: 1
                color: root.line
              }

              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                role: "overline"
                text: "MENU"
                color: root.dim
                bodySize: root.bodySize
              }
              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                role: "caption"
                text: root.lastAction.length
                      ? "Last pick: " + root.lastAction
                      : "Tap the ⋮ in the app bar."
                color: root.dim
                bodySize: root.bodySize
              }

              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                role: "caption"
                text: "Bottom tab: " + root.tabLabel
                color: root.dim
                bodySize: root.bodySize
              }
            }
          }

          Chrome.Fab {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            accent: root.accent
            foreground: root.background
            names: ["list-add-symbolic"]
            tooltip: "Add"
          }
        }

        Chrome.BottomNav {
          id: bottomNav
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.BOTTOM_NAV
          color: root.background
          dim: root.dim
          accent: root.accent
          bodySize: root.bodySize
          currentIndex: root.tab
          onActivated: function (i) {
            root.tab = i
            var t = bottomNav.tabAt(i)
            root.tabLabel = t ? t.text : ""
          }

          Chrome.BottomNavItem {
            text: "Upcoming"
            names: ["view-list-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
          Chrome.BottomNavItem {
            text: "Starred"
            names: ["starred-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
          Chrome.BottomNavItem {
            text: "History"
            names: ["view-grid-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
        }
      }

      Chrome.ContextMenu {
        open: root.menuOpen
        background: root.surface
        line: root.line
        foreground: root.textOnSurface
        danger: (root.colours.hues && root.colours.hues.red)
                ? root.colours.hues.red : "#e01b24"
        bodySize: root.bodySize
        placement: "topEnd"
        onDismissed: root.menuOpen = false

        Chrome.MenuItem {
          names: ["view-pin-symbolic"]
          text: "Pin"
          foreground: root.textOnSurface
          bodySize: root.bodySize
          onClicked: {
            root.lastAction = "Pin"
            root.menuOpen = false
          }
        }
        Chrome.MenuItem {
          names: ["starred-symbolic"]
          text: "Star"
          foreground: root.textOnSurface
          bodySize: root.bodySize
          onClicked: {
            root.lastAction = "Star"
            root.menuOpen = false
          }
        }
        Chrome.MenuItem {
          names: ["user-trash-symbolic"]
          text: "Delete"
          foreground: root.textOnSurface
          danger: (root.colours.hues && root.colours.hues.red)
                  ? root.colours.hues.red : "#e01b24"
          destructive: true
          bodySize: root.bodySize
          onClicked: {
            root.lastAction = "Delete"
            root.menuOpen = false
          }
        }
      }
    }
  }
}
