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
  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    var page = Quickshell.env("MOARCHY_CATALOG_PAGE") || ""
    var at = ["chrome", "boxes", "empty"].indexOf(page)
    if (at >= 0) root.tab = at
  }
  property bool listed: true
  property bool boxed: false
  property bool menuOpen: false
  property bool spinning: false
  property string lastAction: ""
  property int tab: 0
  property string query: ""
  property string mission: ""
  property string both: "Starship"
  property string tabLabel: "Chrome"
  property string chosen: "Weekly"
  property string picked: ""

  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
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
          // The same bar every other app has: TARGET + 12 for the one with
          // the title on it, TARGET + 8 for a search row under it.
          Layout.preferredHeight: Metrics.TARGET + 12
          title: "Chrome"
          foreground: root.textOnSurface
          bodySize: root.bodySize
          leading: Chrome.BackButton {
            colours: root.colours
            color: root.textOnSurface
            onClicked: root.dismiss()
          }
          trailing: Row {
            Chrome.IconButton {
              colours: root.colours
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
              colours: root.colours
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
            colours: root.colours
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

          // ========== every control, once ==========

          Flickable {
            id: flick
            anchors.fill: parent
            visible: root.tab === 0
            clip: true
            contentWidth: width
            contentHeight: col.implicitHeight + Metrics.FAB + Metrics.GUTTER * 2
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: col
              x: Metrics.GUTTER
              y: Metrics.GUTTER
              width: flick.width - Metrics.GUTTER * 2
              spacing: Metrics.GAP

              Chrome.Section {
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                title: "Type"
                cardSpacing: 4

                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "title"; text: "Title"
                  color: root.textOnSurface; bodySize: root.bodySize
                }
                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "subtitle"; text: "Subtitle"
                  color: root.textOnSurface; bodySize: root.bodySize
                }
                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "body"
                  text: "Body. The same Adwaita Sans and body size the shell uses."
                  color: root.textOnSurface; bodySize: root.bodySize
                  wrapMode: Text.WordWrap
                }
                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "caption"
                  text: "Caption, for timestamps and secondary facts."
                  color: root.dim; bodySize: root.bodySize
                }
                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "overline"; text: "Overline"
                  color: root.dim; bodySize: root.bodySize
                }
              }

              Chrome.Section {
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                title: "Fields"
                cardSpacing: 8

                Chrome.TextField {
                  Layout.fillWidth: true
                  placeholderText: "Plain"
                  colours: root.colours
                  bodySize: root.bodySize
                  foreground: root.textOnSurface
                  accent: root.accent
                  placeholderColor: root.dim
                }
                Chrome.TextField {
                  Layout.fillWidth: true
                  leadingNames: ["system-search-symbolic"]
                  placeholderText: "Mission, vehicle, pad"
                  colours: root.colours
                  bodySize: root.bodySize
                  foreground: root.textOnSurface
                  accent: root.accent
                  iconColor: root.dim
                  text: root.mission
                  onTextChanged: root.mission = text
                }
                Chrome.TextField {
                  id: trailingField
                  Layout.fillWidth: true
                  trailingNames: ["edit-clear-symbolic"]
                  trailingClickable: true
                  placeholderText: "Trailing clear"
                  colours: root.colours
                  bodySize: root.bodySize
                  foreground: root.textOnSurface
                  accent: root.accent
                  iconColor: root.dim
                  onTrailingClicked: trailingField.text = ""
                }
                Chrome.TextField {
                  Layout.fillWidth: true
                  leadingNames: ["starred-symbolic"]
                  trailingNames: ["edit-clear-symbolic"]
                  trailingClickable: true
                  placeholderText: "Both icons"
                  colours: root.colours
                  bodySize: root.bodySize
                  foreground: root.textOnSurface
                  accent: root.accent
                  iconColor: root.dim
                  text: root.both
                  onTrailingClicked: root.both = ""
                  onTextChanged: root.both = text
                }
              }

              Chrome.Section {
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                title: "Buttons"
                cardSpacing: 8

                Flow {
                  Layout.fillWidth: true
                  spacing: 8

                  Chrome.Button {
                    colours: root.colours; bodySize: root.bodySize
                    kind: "filled"; text: "Filled"
                    onClicked: root.lastAction = "Filled"
                  }
                  Chrome.Button {
                    colours: root.colours; bodySize: root.bodySize
                    kind: "tonal"; text: "Tonal"
                    onClicked: root.lastAction = "Tonal"
                  }
                  Chrome.Button {
                    colours: root.colours; bodySize: root.bodySize
                    kind: "plain"; text: "Plain"
                    onClicked: root.lastAction = "Plain"
                  }
                  Chrome.Button {
                    colours: root.colours; bodySize: root.bodySize
                    kind: "filled"; destructive: true; text: "Delete"
                    onClicked: root.lastAction = "Delete"
                  }
                  Chrome.Button {
                    colours: root.colours; bodySize: root.bodySize
                    kind: "tonal"; text: "Disabled"; enabled: false
                  }
                }

                Row {
                  Layout.fillWidth: true
                  spacing: 4

                  Chrome.BackButton { colours: root.colours; color: root.textOnSurface }
                  Chrome.IconButton {
                    colours: root.colours
                    color: root.textOnSurface
                    names: ["view-grid-symbolic", "view-app-grid-symbolic"]
                    tooltip: "Grid"
                  }
                  Chrome.IconButton {
                    colours: root.colours
                    color: root.textOnSurface
                    names: ["view-list-symbolic"]
                    tooltip: "List"
                  }
                  Chrome.IconButton {
                    colours: root.colours
                    color: root.accent
                    names: ["starred-symbolic"]
                    tooltip: "Star"
                  }
                }
              }

              Chrome.Section {
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                title: "Chips"

                Flow {
                  Layout.fillWidth: true
                  spacing: 6

                  Repeater {
                    model: ["Once", "Daily", "Weekly", "Monthly", "Yearly"]
                    delegate: Chrome.Chip {
                      id: chip
                      required property string modelData
                      colours: root.colours
                      bodySize: root.bodySize
                      text: chip.modelData
                      on: root.chosen === chip.modelData
                      onClicked: root.chosen = chip.modelData
                    }
                  }
                }
              }

              Chrome.Section {
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                title: "Checks"
                cardSpacing: 0

                Chrome.Check {
                  colours: root.colours
                  checked: root.listed
                  text: root.listed ? "On a list — tap the label" : "Off the list — tap the label"
                  foreground: root.textOnSurface
                  tickColor: Theme.inkOn(root.colours, root.accent)
                  accent: root.accent
                  dim: root.dim
                  bodySize: root.bodySize
                  onToggled: function (on) { root.listed = on }
                }
                Chrome.Check {
                  colours: root.colours
                  checked: root.boxed
                  interactive: false
                  text: "Display only"
                  foreground: root.textOnSurface
                  tickColor: Theme.inkOn(root.colours, root.accent)
                  accent: root.accent
                  dim: root.dim
                  bodySize: root.bodySize
                }
              }

              Chrome.TypedText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                role: "overline"
                text: "Tiles"
                color: root.dim
                bodySize: root.bodySize
              }

              GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Metrics.GAP
                rowSpacing: Metrics.GAP

                Chrome.Tile {
                  Layout.fillWidth: true
                  colours: root.colours; bodySize: root.bodySize
                  label: "Sale ending"; value: "4d 23h 59m"
                  valueColour: root.textOnSurface
                }
                Chrome.Tile {
                  Layout.fillWidth: true
                  colours: root.colours; bodySize: root.bodySize
                  label: "Availability"; value: "10/100"
                  valueColour: root.textOnSurface
                }
                Chrome.Tile {
                  Layout.fillWidth: true
                  colours: root.colours; bodySize: root.bodySize
                  names: ["alarm-symbolic"]
                  label: "With a glyph"; value: "06:40"; footnote: "Weekdays"
                  valueColour: root.textOnSurface
                }
                Chrome.Tile {
                  Layout.fillWidth: true
                  colours: root.colours; bodySize: root.bodySize
                  tint: root.colours.hues ? root.colours.hues.green : root.accent
                  label: "Tinted"; value: "+4.79%"
                  valueColour: root.textOnSurface
                }
              }

              Chrome.TypedText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                role: "overline"
                text: "Rows"
                color: root.dim
                bodySize: root.bodySize
              }

              Chrome.Group {
                id: rowGroup
                Layout.fillWidth: true
                colours: root.colours

                Repeater {
                  model: [
                    { name: "Ada Okonkwo", note: "+44 7700 900412", glyph: "user-home-symbolic" },
                    { name: "Bruno Halvorsen", note: "bruno.h@posteo.de", glyph: "folder-symbolic" },
                    { name: "Carla Reyes", note: "Landlord", glyph: "starred-symbolic" }
                  ]
                  delegate: Chrome.ListRow {
                    id: demoRow
                    required property var modelData
                    Layout.fillWidth: true
                    radius: rowGroup.innerRadius
                    colours: root.colours
                    bodySize: root.bodySize
                    title: demoRow.modelData.name
                    subtitle: demoRow.modelData.note
                    selected: root.picked === demoRow.modelData.name
                    onClicked: root.picked = demoRow.modelData.name

                    leading: Chrome.Icon {
                      anchors.verticalCenter: parent.verticalCenter
                      slot: 32
                      size: 18
                      color: root.accent
                      names: [demoRow.modelData.glyph]
                    }

                    trailing: Chrome.IconButton {
                      colours: root.colours
                      anchors.verticalCenter: parent.verticalCenter
                      slot: 36
                      color: root.dim
                      names: ["view-more-symbolic", "open-menu-symbolic"]
                      tooltip: "More"
                      onClicked: root.menuOpen = true
                    }
                  }
                }
              }

              Chrome.Section {
                Layout.fillWidth: true
                Layout.topMargin: 4
                colours: root.colours
                bodySize: root.bodySize
                title: "What the app bar did"
                cardSpacing: 2

                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "body"
                  text: root.lastAction.length
                        ? "Last pick: " + root.lastAction
                        : "Tap the ⋮ in the app bar."
                  color: root.textOnSurface
                  bodySize: root.bodySize
                }
                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "caption"
                  text: "Bottom tab: " + root.tabLabel + " · chip: " + root.chosen
                  color: root.dim
                  bodySize: root.bodySize
                }
              }
            }
          }

          // ========== the box system itself ==========

          Flickable {
            id: boxFlick
            anchors.fill: parent
            visible: root.tab === 1
            clip: true
            contentWidth: width
            contentHeight: boxCol.implicitHeight + Metrics.GUTTER * 2
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: boxCol
              x: Metrics.GUTTER
              y: Metrics.GUTTER
              width: boxFlick.width - Metrics.GUTTER * 2
              spacing: Metrics.GAP

              // The whole of Theme.LEVEL, drawn. Five steps of the theme's own
              // ink mixed into the theme's own background: on a light palette
              // every one of them is a step *down*, which is the property a
              // picture checks faster than a test can.
              Chrome.Section {
                Layout.fillWidth: true
                colours: root.colours
                bodySize: root.bodySize
                title: "Elevation"
                cardSpacing: 4

                Repeater {
                  model: ["well", "card", "raised", "pressed", "edge"]

                  delegate: Rectangle {
                    id: step
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: Metrics.radius(root.colours, Metrics.RADIUS_SM)
                    color: Theme.surface(root.colours, step.modelData)

                    Chrome.TypedText {
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.left: parent.left
                      anchors.leftMargin: 10
                      role: "caption"
                      text: step.modelData
                      color: root.textOnSurface
                      bodySize: root.bodySize
                    }
                  }
                }
              }

              // The nesting rule, as the thing it describes. Every radius here
              // is Metrics.inner() of the one outside it, so the three curves
              // are concentric -- which is the only way to see it.
              Chrome.TypedText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                role: "overline"
                text: "Nesting"
                color: root.dim
                bodySize: root.bodySize
              }

              Chrome.Group {
                id: nest
                Layout.fillWidth: true
                colours: root.colours
                spacing: Metrics.GROUP_PAD

                Repeater {
                  model: 2

                  delegate: Rectangle {
                    id: inner
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    radius: nest.innerRadius
                    color: Theme.surface(root.colours, "raised")

                    Chrome.TypedText {
                      anchors.top: parent.top
                      anchors.left: parent.left
                      anchors.margins: 8
                      role: "caption"
                      text: "radius " + inner.radius
                      color: root.dim
                      bodySize: root.bodySize
                    }

                    Rectangle {
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      anchors.margins: Metrics.GROUP_PAD
                      width: 96
                      height: 28
                      radius: Metrics.inner(inner.radius, Metrics.GROUP_PAD)
                      color: Theme.surface(root.colours, "pressed")

                      Chrome.TypedText {
                        anchors.centerIn: parent
                        role: "caption"
                        text: "radius " + parent.radius
                        color: root.dim
                        bodySize: root.bodySize
                      }
                    }
                  }
                }
              }

              Chrome.Card {
                Layout.fillWidth: true
                colours: root.colours
                level: "well"

                Chrome.TypedText {
                  Layout.fillWidth: true
                  role: "caption"
                  text: "A box inside a box takes the outer radius less the gap "
                        + "between the two edges — " + Metrics.RADIUS_LG + " less "
                        + Metrics.GROUP_PAD + " is " + Metrics.RADIUS_MD
                        + ", and " + Metrics.RADIUS_MD + " less " + Metrics.GROUP_PAD
                        + " is " + Metrics.RADIUS_SM + ". Anything else leaves a "
                        + "crescent of the outer fill in every corner."
                  color: root.dim
                  bodySize: root.bodySize
                  wrapMode: Text.WordWrap
                }
              }

              Chrome.TypedText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                role: "overline"
                text: "Hues"
                color: root.dim
                bodySize: root.bodySize
              }

              Chrome.Group {
                Layout.fillWidth: true
                colours: root.colours
                spacing: Metrics.GROUP_PAD

                Repeater {
                  model: ["red", "orange", "yellow", "green", "cyan", "blue", "magenta", "brown"]

                  delegate: Rectangle {
                    id: hueRow
                    required property string modelData
                    readonly property color hue: root.colours.hues
                                                 ? root.colours.hues[hueRow.modelData]
                                                 : root.accent
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    radius: Metrics.radius(root.colours, Metrics.RADIUS_MD)
                    color: Theme.tint(root.colours, hueRow.hue, "card")

                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.left: parent.left
                      anchors.leftMargin: 8
                      width: 18
                      height: 18
                      radius: Metrics.round(root.colours, width)
                      color: hueRow.hue
                    }

                    Chrome.TypedText {
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.left: parent.left
                      anchors.leftMargin: 34
                      role: "caption"
                      text: hueRow.modelData
                      color: root.textOnSurface
                      bodySize: root.bodySize
                    }
                  }
                }
              }
            }
          }

          // ========== what a screen says when there is nothing on it =====

          Item {
            anchors.fill: parent
            visible: root.tab === 2

            Chrome.EmptyState {
              anchors.centerIn: parent
              width: parent.width - Metrics.GUTTER * 2
              colours: root.colours
              bodySize: root.bodySize
              names: ["system-search-symbolic"]
              title: "Nothing matches"
              detail: "Every app here draws this one rather than a grey sentence "
                      + "floating in the middle of a black rectangle."
            }
          }

          Chrome.Toast {
            id: toast
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            colours: root.colours
            bodySize: root.bodySize
          }

          Chrome.Fab {
            colours: root.colours
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            accent: root.accent
            foreground: Theme.inkOn(root.colours, root.accent)
            names: ["list-add-symbolic"]
            tooltip: "Add"
            onClicked: toast.show("A toast, which is the kit's only spinner.")
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
            text: "Chrome"
            names: ["view-list-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
          Chrome.BottomNavItem {
            text: "Boxes"
            names: ["view-grid-symbolic", "view-app-grid-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
          Chrome.BottomNavItem {
            text: "Empty"
            names: ["action-unavailable-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
        }
      }

      Chrome.ContextMenu {
        open: root.menuOpen
        colours: root.colours
        background: root.background
        foreground: root.textOnSurface
        danger: (root.colours.hues && root.colours.hues.red)
                ? root.colours.hues.red : "#e01b24"
        bodySize: root.bodySize
        placement: "topEnd"
        onDismissed: root.menuOpen = false

        Chrome.MenuItem {
          colours: root.colours
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
          colours: root.colours
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
          colours: root.colours
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
