import QtQuick
import "kit"

// How often it reads, the look, the app menu entry, and what it is.
SettingsPage {
  id: root
  blurb: app.sample && app.sample.machine.kernel
    ? (app.sample.machine.model || app.sample.machine.host) + " · Linux " + app.sample.machine.kernel
    : "A task manager, out of /proc and /sys"

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

  AppearanceSection { app: root.app }
  LauncherSection { app: root.app }
  KeysSection {
    app: root.app
    keys: [
      ["1 – 5", "Overview, Processor, Memory, Tasks, Network"],
      ["Space", "Pause or resume the readings"],
      ["/", "Search tasks"],
      ["↑ ↓  Enter", "Move through tasks, open one"],
      ["a  s", "Apps or all processes; next sort order"],
      ["Delete", "End the task (Shift for force stop)"],
      [",", "Settings"],
      ["Esc", "Back one step"]
    ]
  }

  SettingsSection {
    app: root.app
    width: parent.width
    title: "Where the numbers come from"
    note: "/proc and /sys, read by one sh and one awk each tick, and df for how full a filesystem is. No daemon, nothing installed beside it, and nothing leaves this computer. Ending a task sends it a signal with kill; a process that belongs to another user is refused by the kernel."
  }
}
