import QtQuick
import "Api.mjs" as Api

// How to travel -- what to ride, how fast you walk, step-free or not, how
// many changes -- and the clock, the launcher entry and the saved data.
Item {
  id: root
  property var app
  property alias flick: flick

  function refresh(force) {}

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: body.implicitHeight + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    Column {
      id: body
      x: 16
      y: 8
      width: Math.min(flick.width - 32, 640)
      spacing: 22

      SettingsSection {
        app: root.app
        width: body.width
        title: "Ride"
        note: "Journeys and saved trips use only these. At least one stays on."
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: Api.GROUPS
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData.label
              selected: root.app.store.groups.indexOf(modelData.key) >= 0
              onClicked: root.app.store.toggleGroup(modelData.key)
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "Changes"
        note: "The most changes a journey may have."
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: [{ v: -1, l: "Any" }, { v: 0, l: "Direct only" }, { v: 1, l: "Up to 1" }, { v: 2, l: "Up to 2" }, { v: 3, l: "Up to 3" }]
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData.l
              selected: root.app.store.maxTransfers === modelData.v
              onClicked: root.app.store.set("maxTransfers", modelData.v)
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "Walking"
        note: "How fast you walk sets how much time a change needs. Step-free avoids stairs where the data says where they are."
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: [{ v: "slow", l: "Slow" }, { v: "normal", l: "Normal" }, { v: "fast", l: "Fast" }]
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData.l
              selected: root.app.store.walk === modelData.v
              onClicked: root.app.store.set("walk", modelData.v)
            }
          }
          Chip {
            app: root.app
            text: "Step-free"
            selected: root.app.store.wheelchair
            onClicked: root.app.store.set("wheelchair", !root.app.store.wheelchair)
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "Clock"
        note: "Times are shown in this device's time zone."
        Row {
          spacing: 6
          Chip { app: root.app; text: "24-hour"; selected: root.app.store.clock24; onClicked: root.app.store.set("clock24", true) }
          Chip { app: root.app; text: "12-hour"; selected: !root.app.store.clock24; onClicked: root.app.store.set("clock24", false) }
        }
      }

      // On a phone the shell keeps this entry itself, in its app drawer.
      SettingsSection {
        visible: !root.app.compact
        app: root.app
        width: body.width
        title: "App launcher"
        note: "Transit has an entry in Omarchy's app menu, so you can open it by name. The entry is the file ~/.local/share/applications/omarchy-plugin-" + root.app.pluginId + ".desktop."
        Row {
          spacing: 6
          Chip {
            app: root.app
            text: "Show"
            selected: root.app.store.prefs.launcher !== false
            onClicked: root.app.launcher.setShown(true)
          }
          Chip {
            app: root.app
            text: "Hide"
            selected: root.app.store.prefs.launcher === false
            onClicked: root.app.launcher.setShown(false)
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "Saved data"
        note: "The last boards and journeys are kept on disk so the app opens instantly. Recent searches are kept in the app's settings."
        Flow {
          width: parent.width
          spacing: 6
          Chip {
            app: root.app
            text: "Clear saved boards"
            onClicked: { root.app.motis.clear(); root.app.store.clearSnapshot(); root.app.refresh(true) }
          }
          Chip {
            app: root.app
            text: "Clear recent searches"
            onClicked: root.app.store.set("recents", [])
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "About"
        note: "Transit " + (root.app.manifest && root.app.manifest.version ? root.app.manifest.version : Api.VERSION)
          + ". Journeys and departures come from Transitous, a free, community-run router built on open timetables. "
          + "Live times, platforms and notices are shown where the local operator publishes them; elsewhere the times are the timetable's."
        Flow {
          width: parent.width
          spacing: 6
          Chip {
            app: root.app
            text: "Transitous ↗"
            onClicked: Qt.openUrlExternally("https://transitous.org")
          }
          Chip {
            app: root.app
            text: "Data sources ↗"
            onClicked: Qt.openUrlExternally("https://transitous.org/sources/")
          }
          Chip {
            app: root.app
            text: "© OpenStreetMap ↗"
            onClicked: Qt.openUrlExternally("https://www.openstreetmap.org/copyright")
          }
        }
      }
    }
  }
}
