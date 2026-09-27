import QtQuick
import "Glyphs.js" as G

// How often it reads, the look, the app menu entry, and what it is.
Item {
  id: root
  property var app

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: body.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      x: root.app.compact ? 16 : 26
      y: 8
      width: Math.min(flick.width - x * 2, 680)
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
          Mark { anchors.verticalCenter: parent.verticalCenter; size: 56 }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 72
            spacing: 3
            Text {
              text: "Vitals" + (root.app.version ? " " + root.app.version : "")
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.lg + 2
              font.weight: Font.Bold
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: root.app.sample && root.app.sample.machine.kernel
                ? (root.app.sample.machine.model || root.app.sample.machine.host) + " · Linux " + root.app.sample.machine.kernel
                : "A task manager, out of /proc and /sys"
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: parent.width
        title: "Update every"
        note: "A processor reading is the difference between two samples, so a shorter interval measures a shorter span and shows more noise as load, and costs more work a minute. Nothing is read while the window is closed."
        Row {
          spacing: 8
          Repeater {
            model: [1000, 2000, 5000]
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData / 1000 + " s"
              selected: root.app.interval === modelData
              onClicked: root.app.store.set("interval", modelData)
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: parent.width
        title: "Appearance"
        note: root.app.inShell || root.app.hostTheme.hasFile
          ? "Omarchy's theme, as the shell draws it, and it changes when the theme does. Light or dark sets a plain palette instead."
          : "No Omarchy theme here, so it follows the desktop's light or dark preference, unless you pick one."
        Flow {
          width: parent.width
          spacing: 8
          Repeater {
            model: (root.app.inShell || root.app.hostTheme.hasFile ? [{ k: "theme", l: "Omarchy theme" }] : [])
              .concat([{ k: "system", l: "System" }, { k: "light", l: "Light" }, { k: "dark", l: "Dark" }])
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData.l
              // "theme" with no theme to follow is the desktop's preference.
              selected: {
                var a = root.app.store.prefs.appearance || "theme"
                if (a === "theme" && !(root.app.inShell || root.app.hostTheme.hasFile)) a = "system"
                return a === modelData.k
              }
              onClicked: root.app.store.set("appearance", modelData.k)
            }
          }
        }
      }

      SettingsSection {
        visible: root.app.launcher.active
        app: root.app
        width: parent.width
        title: "App menu"
        note: "An entry in the app launcher that opens Vitals in this shell."
        Row {
          spacing: 8
          Chip { app: root.app; text: "Shown"; selected: root.app.store.prefs.launcher !== false; onClicked: root.app.launcher.setShown(true) }
          Chip { app: root.app; text: "Hidden"; selected: root.app.store.prefs.launcher === false; onClicked: root.app.launcher.setShown(false) }
        }
      }

      SettingsSection {
        visible: !root.app.compact
        app: root.app
        width: parent.width
        title: "Keys"
        Column {
          spacing: 6
          Repeater {
            model: [
              ["1 – 5", "Overview, Processor, Memory, Tasks, Network"],
              ["Space", "Pause or resume the readings"],
              ["/", "Search tasks"],
              ["↑ ↓  Enter", "Move through tasks, open one"],
              ["a  s", "Apps or all processes; next sort order"],
              ["Delete", "End the task (Shift for force stop)"],
              [",", "Settings"],
              ["Esc", "Back one step"]
            ]
            delegate: Row {
              required property var modelData
              Text {
                width: 110
                text: modelData[0]
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
                font.weight: Font.DemiBold
              }
              Text {
                text: modelData[1]
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
              }
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: parent.width
        title: "Where the numbers come from"
        note: "/proc and /sys, read by one sh and one awk each tick, and df for how full a filesystem is. No daemon, nothing installed beside it, and nothing leaves this computer. Ending a task sends it a signal with kill; a process that belongs to another user is refused by the kernel."
      }
    }
  }
}
