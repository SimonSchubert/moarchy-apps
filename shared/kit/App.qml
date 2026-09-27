import QtQuick
import Quickshell
import Quickshell.Io
import "Glyphs.js" as KG

// The part of every app that is not the app: the window, the host API, the
// theme, the two layouts and the way back out.
//
// An app's Panel.qml is one of these:
//
//   App {
//     id: root
//     appId: "org.moarchy.habits"
//     title: "Habits"
//     store: Store { name: "moarchy-habits" }
//     tabs: [{ key: "today", label: "Today", glyph: G.today }, ...]
//     settings: Component { SettingsView { app: root } }
//     TodayView { anchors.fill: parent; app: root; visible: root.tab === "today" }
//   }
//
// Inside the Omarchy shell the host instantiates Panel.qml, hands it `shell`
// and `manifest`, and calls open(), close() and back(). Under a plain
// Quickshell, shell.qml does the same with `standalone: true`.
//
// The layout is chosen by the window's width, never by the device: below
// 720 px it is a phone app -- tabs at the bottom, one column, pages that stack
// over the tab with a back arrow -- and above it a desktop one, with a rail of
// pages on the left and room for panes beside each other. On Omarchy Mobile
// the window is the whole screen, so the phone is always the narrow case.
Item {
  id: root

  // ------------------------------------------------------------ host API

  property var shell: null
  property var manifest: null
  property bool opened: false
  // True when shell.qml runs it as its own process, with no Omarchy shell.
  property bool standalone: false

  // The plugin id, for a host that did not hand over a manifest.
  property string appId: ""
  readonly property string pluginId: manifest && manifest.id ? manifest.id : appId
  property string title: ""
  // Under the title: a count, a date, where the numbers came from.
  property string subtitle: ""
  // What the header says when it is not the app's name: the town a weather
  // app is showing, the folder a file manager is in. The window, the launcher
  // and Settings keep `title`.
  property string heading: ""

  // The app's own folder: where manifest.json and icon.svg are. The kit is
  // vendored into it as kit/, so its parent is the app.
  property string appDir: String(Qt.resolvedUrl("..")).replace(/^file:\/\//, "").replace(/\/$/, "")

  // The payload the last open() was given, parsed: {} when there was none.
  signal summoned(var payload)

  function open(payloadJson) {
    theme.reload()
    var payload = ({})
    try { if (payloadJson) payload = JSON.parse(payloadJson) || ({}) } catch (e) {}
    opened = true
    window.visible = true
    summoned(payload)
    Qt.callLater(resetFocus)
  }

  // From the host (`shell hide`, the keybinding). The window goes without
  // telling the host back: it already knows.
  property bool closingFromHost: false
  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
    opened = false
  }

  function toggle() { opened ? close() : open("") }

  // Closing from inside -- the window manager, a Quit button -- goes through
  // the host. Dropping `opened` alone leaves the host counting the panel open,
  // and the next `shell toggle` would "hide" it and show nothing.
  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  // ------------------------------------------------------------ theme

  // Required: every app has preferences, if only its appearance.
  property Store store: null

  readonly property HostTheme hostTheme: HostTheme {
    id: theme
    appearance: root.store && root.store.prefs.appearance ? root.store.prefs.appearance : "theme"
  }
  readonly property bool inShell: theme.inShell

  // Narrower than this is a phone.
  property int breakpoint: 720
  readonly property bool compact: stage.width < breakpoint

  property Tokens ui: Tokens { theme: root.hostTheme; compact: root.compact }

  // A colour at an opacity. `c` may be a color or a "#rrggbb" string: a
  // string has no .r, and Qt.rgba(undefined, ...) is black.
  function alpha(c, a) { var x = Qt.color(c); return Qt.rgba(x.r, x.g, x.b, a) }

  // Omarchy Mobile draws its gesture bar over the bottom of every app, on
  // purpose: an app's background reaches the glass, and its controls stay
  // above the strip. 20 px, as the phone's Tokens.gestureHeight, and only
  // where the phone's gesture bar is installed.
  property bool gestureBar: false
  readonly property int bottomInset: gestureBar && compact ? 20 : 0
  FileView {
    path: "/usr/share/omarchy/shell/plugins/mobile/gesture-bar/manifest.json"
    preload: true
    printErrors: false
    onLoaded: root.gestureBar = true
  }

  // ------------------------------------------------------------ pages

  // [{ key, label, glyph }]. None or one: no rail and no tab bar, just the
  // header and the content -- a game, a calculator.
  property var tabs: []
  property string tab: tabs.length ? tabs[0].key : ""
  readonly property string homeTab: tabs.length ? tabs[0].key : ""
  readonly property bool tabbed: tabs.length > 1
  // Shown as a page of its own: the last item in the rail, a gear in the
  // header on a phone, and `,` on a keyboard.
  property Component settings: null
  readonly property bool inSettings: tab === "settings"
  readonly property bool hasRail: !compact && tabbed

  // Pages over the current tab: plain objects, drawn by `page`, which reads
  // the top one as `app.topPage`. Capped, so a long walk from page to page does
  // not keep every page alive.
  property var stack: []
  readonly property var topPage: stack.length ? stack[stack.length - 1] : null
  property Component page: null
  property int maxDepth: 6

  // The header: false for an app that draws its own (a game's board edge to
  // edge), true otherwise.
  property bool header: true
  // Drawn at the right of the header: IconButtons, as a Row's children.
  property Component actions: null
  // The app's mark, in the rail and in the header of its first tab on a
  // phone. An Item of any size; it is scaled to fit 30 px.
  property Component mark: null
  // Under the title in the rail: what the app is, or whose it is.
  property string caption: ""
  // At the foot of the rail, when there is room for it.
  property Component railFooter: null

  // The content: the app's views, filling the area under the header.
  default property alias content: views.data
  readonly property alias contentArea: views
  // Where a Dialog puts itself: over everything, the header included.
  readonly property alias overlay: overlayLayer

  function setTab(key) {
    resetFocus()
    stack = []
    tab = key
    tabSelected(key)
  }
  signal tabSelected(string key)

  function push(entry) {
    resetFocus()
    var s = stack.slice()
    if (s.length >= maxDepth) s.splice(0, s.length - maxDepth + 1)
    s.push(entry)
    stack = s
  }
  function pop() {
    if (!stack.length) return false
    var s = stack.slice()
    s.pop()
    stack = s
    return true
  }

  // The open Dialog, if any. Back closes it first.
  property var dialog: null

  // One step out of wherever the app is, before the tabs are: a search query
  // cleared, a selection dropped. function () -> true when it stepped.
  property var stepBack: null

  // One step out: a dialog, a page, the app's own step, settings, the first
  // tab, then nothing. True when it stepped. On a phone the gesture bar calls
  // this directly and hides the panel itself when it answers false, so at the
  // root it must not also close.
  function back() {
    resetFocus()
    if (dialog) { dialog.close(); return true }
    if (pop()) return true
    if (typeof stepBack === "function" && stepBack()) return true
    if (tab !== homeTab) { setTab(homeTab); return true }
    return false
  }

  // Keys the app handles itself, before the kit's own (Escape, the digits
  // for tabs, `,` for settings): function (event) -> nothing; accept the
  // event to keep it.
  property var keyHandler: null

  // Focus back to the window, off any text field, so the phone's keyboard
  // goes down.
  function resetFocus() { keys.forceActiveFocus() }

  // ------------------------------------------------------------ toasts

  property string toastText: ""
  // A word on the toast that does something -- Undo, after a delete -- and
  // what it does. A toast with one stays up longer: it is a choice to make.
  property string toastAction: ""
  property var toastCallback: null
  function toast(text, actionText, action) {
    toastText = text
    toastAction = actionText && typeof action === "function" ? actionText : ""
    toastCallback = toastAction ? action : null
    toastTimer.interval = toastAction ? 5000 : 2600
    toastTimer.restart()
  }
  function toastActed() {
    var act = toastCallback
    toastText = ""
    toastAction = ""
    toastCallback = null
    toastTimer.stop()
    if (typeof act === "function") act()
  }
  Timer {
    id: toastTimer
    interval: 2600
    onTriggered: { root.toastText = ""; root.toastAction = ""; root.toastCallback = null }
  }

  // ------------------------------------------------------------ plumbing

  Component.onCompleted: {
    theme.probe(root)
    if (standalone) Qt.callLater(function () { root.open(Quickshell.env("MOARCHY_PAYLOAD") || "") })
  }

  onOpenedChanged: if (!opened) {
    if (dialog) dialog.close()
    stack = []
    // Its own process: closing the window is quitting. The last save is
    // written first; saves are asynchronous, and a moment is enough.
    if (standalone) {
      if (store) store.flush()
      quitting()
      quitTimer.start()
    }
  }
  // Before a standalone quit: for an app with files of its own to flush.
  signal quitting()

  Timer {
    id: quitTimer
    interval: 500
    onTriggered: Qt.quit()
  }
  // MOARCHY_QUIT_AFTER=6 -- for headless runs: a run that does not end is a
  // run that hangs CI.
  Timer {
    interval: 1000 * parseInt(Quickshell.env("MOARCHY_QUIT_AFTER") || "0", 10)
    running: root.standalone && interval > 0
    onTriggered: Qt.quit()
  }

  // The version, for Settings: the shell hands the manifest over, shell.qml
  // does not.
  property string ownVersion: ""
  readonly property string version: manifest && manifest.version ? manifest.version : ownVersion
  FileView {
    path: root.appDir + "/manifest.json"
    preload: root.manifest === null
    printErrors: false
    onLoaded: {
      try { root.ownVersion = String(JSON.parse(text()).version || "").slice(0, 20) } catch (e) {}
    }
  }

  // The app-menu entry the plugin writes for itself when installed without
  // its package. Set its name and the rest from the app.
  readonly property alias launcher: launcherObj
  LauncherEntry {
    id: launcherObj
    app: root
    pluginId: root.pluginId
    name: root.title
    appDir: root.appDir
  }

  property int windowWidth: 1240
  property int windowHeight: 820

  // ------------------------------------------------------------ window

  // Shown and hidden by open() and close(), not bound to `opened`: the window
  // manager closes it too, and a binding would fight that.
  FloatingWindow {
    id: window
    visible: false
    title: root.title
    color: root.ui.bg
    implicitWidth: root.windowWidth
    implicitHeight: root.windowHeight
    minimumSize: Qt.size(360, 480)

    onVisibleChanged: if (!visible && !root.closingFromHost && root.opened) root.dismiss()

    Item {
      id: stage
      anchors.fill: parent

      Rectangle {
        anchors.fill: parent
        color: root.ui.bg
        clip: true

        // A plain Item and not a FocusScope: forceActiveFocus() on a scope
        // hands focus back to whatever inside it had it last -- a search
        // field -- and the phone's keyboard comes straight back up.
        Item {
          id: keys
          anchors.fill: parent
          focus: true

          Keys.onPressed: function (event) {
            var k = event.key
            if (k === Qt.Key_Escape || k === Qt.Key_Back) { root.back(); event.accepted = true; return }
            if (root.dialog) {
              if (k === Qt.Key_Return || k === Qt.Key_Enter) { root.dialog.accept(); event.accepted = true }
              return
            }
            if (typeof root.keyHandler === "function") {
              root.keyHandler(event)
              if (event.accepted) return
            }
            if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
            if (root.tabbed && event.text !== "") {
              var n = "123456789".indexOf(event.text)
              if (n >= 0 && n < root.tabs.length) { root.setTab(root.tabs[n].key); event.accepted = true; return }
            }
            if (event.text === "," && root.settings) { root.setTab("settings"); event.accepted = true }
          }

          // ---------------------------------------------------- rail
          Rectangle {
            id: rail
            // Only for an app with pages to choose between. One with a single
            // screen -- a game -- keeps the width, and its Settings is a gear.
            visible: root.hasRail
            width: visible ? 216 : 0
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: root.ui.surface

            Column {
              anchors.fill: parent
              anchors.topMargin: 18
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              spacing: 2

              Row {
                x: 6
                height: 44
                spacing: 10
                Loader {
                  active: root.mark !== null
                  visible: active
                  anchors.verticalCenter: parent.verticalCenter
                  width: 30
                  height: 30
                  sourceComponent: root.mark
                }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  Text {
                    text: root.title
                    color: root.ui.text
                    font.family: root.ui.font
                    font.pixelSize: 19
                    font.weight: Font.Bold
                  }
                  Text {
                    visible: root.caption !== ""
                    text: root.caption
                    color: root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                    width: 150
                    elide: Text.ElideRight
                  }
                }
              }
              Item { width: 1; height: 14 }

              Repeater {
                model: (root.tabbed ? root.tabs : [])
                  .concat(root.settings ? [{ key: "settings", label: "Settings", glyph: KG.settings }] : [])
                delegate: Rectangle {
                  id: railItem
                  required property var modelData
                  required property int index
                  readonly property bool current: root.tab === modelData.key
                  readonly property bool last: modelData.key === "settings" && root.tabbed
                  width: parent.width
                  height: 40
                  radius: root.ui.radius
                  color: current ? root.ui.accentSoft : railMouse.containsMouse ? root.ui.hover : "transparent"
                  Accessible.role: Accessible.PageTab
                  Accessible.name: modelData.label
                  Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 8
                    spacing: 8
                    Icon { app: root; text: railItem.modelData.glyph || ""; size: 18; color: railItem.current ? root.ui.accent : root.ui.text }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: railItem.modelData.label
                      color: railItem.current ? root.ui.accent : root.ui.text
                      font.family: root.ui.font
                      font.pixelSize: root.ui.fs.md
                      font.weight: railItem.current ? Font.DemiBold : Font.Normal
                    }
                  }
                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.tabbed && (railItem.last || railItem.index < 9)
                    text: railItem.modelData.key === "settings" ? "," : railItem.index + 1
                    color: root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                  }
                  Rectangle {
                    visible: railItem.last
                    y: -6
                    x: 8
                    width: parent.width - 16
                    height: 1
                    color: root.ui.divider
                  }
                  MouseArea {
                    id: railMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setTab(railItem.modelData.key)
                  }
                }
              }
            }

            Loader {
              active: root.railFooter !== null && rail.height >= 520
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 16
              x: 20
              width: parent.width - 40
              sourceComponent: root.railFooter
            }
          }

          // ---------------------------------------------------- main
          // Everything right of the rail (all of it, on a phone).
          Item {
            id: main
            anchors.left: rail.visible ? rail.right : parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: nav.visible ? nav.top : parent.bottom
            anchors.bottomMargin: nav.visible ? 0 : root.bottomInset

            Item {
              id: head
              visible: root.header
              width: parent.width
              height: visible ? (root.compact ? 60 : 68) : 0

              IconButton {
                id: headBack
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                // Settings is a page wherever there is no rail to leave it by.
                visible: root.inSettings && !root.hasRail
                width: visible ? implicitWidth : 0
                app: root
                glyph: KG.back
                label: "Back"
                onClicked: root.back()
              }
              Row {
                anchors.left: headBack.visible ? headBack.right : parent.left
                anchors.leftMargin: headBack.visible ? 4 : (root.compact ? 16 : 26)
                anchors.right: headActions.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                // The app's mark where the rail is not showing it.
                readonly property bool marked: root.mark !== null && !root.hasRail && root.tab === root.homeTab && !root.inSettings
                Loader {
                  active: parent.marked
                  visible: active
                  anchors.verticalCenter: parent.verticalCenter
                  width: 30
                  height: 30
                  sourceComponent: root.mark
                }
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - (parent.marked ? 40 : 0)
                  Text {
                    width: parent.width
                    text: root.headTitle()
                    color: root.ui.text
                    font.family: root.ui.font
                    font.pixelSize: root.compact ? 21 : 24
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    visible: !root.inSettings && root.subtitle !== ""
                    text: root.subtitle
                    color: root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                    elide: Text.ElideRight
                  }
                }
              }
              Row {
                id: headActions
                anchors.right: parent.right
                anchors.rightMargin: root.compact ? 4 : 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Loader {
                  active: root.actions !== null && !root.inSettings
                  visible: active
                  anchors.verticalCenter: parent.verticalCenter
                  sourceComponent: root.actions
                }
                IconButton {
                  visible: !root.hasRail && root.settings !== null && !root.inSettings
                  anchors.verticalCenter: parent.verticalCenter
                  app: root
                  glyph: KG.settings
                  label: "Settings"
                  onClicked: root.setTab("settings")
                }
              }
            }

            Item {
              id: views
              anchors.top: head.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              visible: !root.inSettings
            }

            Loader {
              anchors.fill: views
              active: root.inSettings && root.settings !== null
              sourceComponent: root.settings
            }
          }

          // A page over the whole of the main side, header included. The
          // page draws its own header (PageHeader) with a way back.
          Loader {
            id: pageLoader
            z: 3
            active: root.topPage !== null && root.page !== null
            anchors.left: main.left
            anchors.right: main.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.bottomInset
            sourceComponent: Rectangle {
              color: root.ui.bg
              MouseArea { anchors.fill: parent }
              Loader { anchors.fill: parent; sourceComponent: root.page }
            }
          }

          // ---------------------------------------------------- tabs
          // Phone only, and not under a page.
          Rectangle {
            id: nav
            z: 4
            visible: root.compact && root.tabbed && root.topPage === null && !root.inSettings
            anchors.bottom: parent.bottom
            width: parent.width
            height: visible ? 64 + root.bottomInset : 0
            color: root.ui.surface

            Row {
              width: parent.width
              height: 64
              Repeater {
                model: root.tabs
                delegate: Item {
                  id: navItem
                  required property var modelData
                  readonly property bool current: root.tab === modelData.key
                  width: nav.width / root.tabs.length
                  height: 64
                  Accessible.role: Accessible.PageTab
                  Accessible.name: modelData.label

                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    width: 56
                    height: 30
                    radius: 15
                    color: navItem.current ? root.ui.accentSoft : navMouse.pressed ? root.ui.pressed : "transparent"
                  }
                  Icon {
                    app: root
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    height: 30
                    text: navItem.modelData.glyph || ""
                    size: 20
                    color: navItem.current ? root.ui.accent : root.ui.muted
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 41
                    width: parent.width - 4
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: navItem.modelData.label
                    color: navItem.current ? root.ui.text : root.ui.muted
                    font.family: root.ui.font
                    font.pixelSize: root.ui.fs.xs
                    font.weight: navItem.current ? Font.DemiBold : Font.Normal
                  }
                  MouseArea {
                    id: navMouse
                    anchors.fill: parent
                    onClicked: root.setTab(navItem.modelData.key)
                  }
                }
              }
            }
          }

          // Dialogs, over everything.
          Item {
            id: overlayLayer
            z: 10
            anchors.fill: parent
          }

          // ---------------------------------------------------- toast
          Rectangle {
            z: 20
            anchors.horizontalCenter: main.horizontalCenter
            anchors.bottom: main.bottom
            anchors.bottomMargin: 16
            width: Math.min(toastRow.implicitWidth + 36, main.width - 32)
            height: root.toastAction ? 44 : 40
            radius: height / 2
            color: root.ui.text
            opacity: root.toastText !== "" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Row {
              id: toastRow
              anchors.centerIn: parent
              spacing: 16
              Text {
                id: toastLabel
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, main.width - 80 - (toastButton.visible ? toastButton.width + 16 : 0))
                text: root.toastText
                color: root.ui.bg
                font.family: root.ui.font
                font.pixelSize: root.ui.fs.sm
                font.weight: Font.DemiBold
                elide: Text.ElideRight
              }
              Text {
                id: toastButton
                visible: root.toastAction !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: root.toastAction
                color: Qt.tint(root.ui.bg, root.alpha(root.ui.accent, 0.8))
                font.family: root.ui.font
                font.pixelSize: root.ui.fs.sm
                font.weight: Font.Bold
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -12
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toastActed()
                }
              }
            }
          }
        }
      }
    }
  }

  function headTitle() {
    if (inSettings) return "Settings"
    if (heading !== "") return heading
    if (!hasRail && tab === homeTab) return title
    for (var i = 0; i < tabs.length; i++) if (tabs[i].key === tab) return tabbed ? tabs[i].label : title
    return title
  }
}
