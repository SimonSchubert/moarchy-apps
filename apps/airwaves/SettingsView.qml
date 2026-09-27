import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// Which country Discover shows, logos, the look, the app menu entry, and
// what is kept on disk.
Item {
  id: root
  property var app

  readonly property var countries: { app.api.revision; return app.api.peek(Api.countriesPath()) || [] }
  property string countryQuery: ""
  readonly property var countryMatches: {
    var q = countryQuery.trim().toLowerCase()
    if (!q) return []
    return countries.filter(function (c) { return c.name.toLowerCase().indexOf(q) >= 0 || c.code.toLowerCase() === q }).slice(0, 8)
  }
  property bool confirmClear: false

  function refresh(force) { app.api.want(Api.countriesPath(), "countries", force ? 0 : 86400000, false) }

  Timer { id: confirmTimer; interval: 3000; onTriggered: root.confirmClear = false }

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: body.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    Column {
      id: body
      x: root.app.compact ? 16 : 24
      y: 8
      width: Math.min(flick.width - x * 2, 680)
      spacing: 26

      // ------------------------------------------------ the directory
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
              text: "Airwaves"
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.lg + 2
              font.weight: Font.Bold
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: root.app.store.favorites.length + (root.app.store.favorites.length === 1 ? " favourite" : " favourites")
                + " · " + root.app.store.recent.length + " played recently"
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "Your country"
        note: "Discover shows what is popular here. " + (root.app.store.prefs.country
          ? "Chosen by you."
          : root.app.country ? "Taken from this computer's language settings." : "This computer doesn't say, so pick one.")
        Row {
          spacing: 6
          Chip {
            visible: root.app.country !== ""
            app: root.app
            glyph: G.marker
            text: root.app.countryName
            selected: true
          }
          Chip {
            visible: root.app.store.prefs.country !== ""
            app: root.app
            text: "Use this computer's"
            onClicked: { root.app.store.set("country", ""); root.countryQuery = "" }
          }
        }
        Field {
          width: Math.min(parent.width, 360)
          app: root.app
          numeric: false
          placeholder: "Find another country"
          text: root.countryQuery
          onEdited: function (v) { root.countryQuery = v }
        }
        Flow {
          width: parent.width
          spacing: 6
          visible: root.countryMatches.length > 0
          Repeater {
            model: root.countryMatches
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData.name
              onClicked: {
                root.app.store.set("country", modelData.code)
                root.countryQuery = ""
                root.app.resetFocus()
                root.app.toast("Discover shows " + modelData.name)
              }
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "Station logos"
        note: "Logos are downloaded from each station's own website, so those sites see a request from you. Hidden, stations wear their colour and initials instead, and nothing is fetched outside radio-browser.info."
        Row {
          spacing: 6
          Chip { app: root.app; text: "Show"; selected: root.app.store.prefs.logos !== false; onClicked: root.app.store.set("logos", true) }
          Chip { app: root.app; text: "Hide"; selected: root.app.store.prefs.logos === false; onClicked: root.app.store.set("logos", false) }
        }
      }

      // Inside the Omarchy shell the shell's theme is the look.
      SettingsSection {
        visible: !root.app.inShell
        app: root.app
        width: body.width
        title: "Appearance"
        note: "System follows your desktop's light or dark preference."
        Row {
          spacing: 6
          Repeater {
            model: [{ k: "system", l: "System" }, { k: "light", l: "Light" }, { k: "dark", l: "Dark" }]
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData.l
              selected: root.app.store.prefs.appearance === modelData.k
              onClicked: root.app.store.set("appearance", modelData.k)
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "Player"
        note: root.app.player.missing
          ? "Airwaves plays through mpv, which isn't installed. Install it with: sudo pacman -S mpv"
          : "Airwaves plays through mpv, and uses your own mpv settings: an audio device chosen in ~/.config/mpv/mpv.conf applies here, and so do scripts such as mpv-mpris, which puts the station on your media keys and lock screen."
            + (root.app.inShell ? " Closing the window keeps the music playing; stop it first to end it." : "")
      }

      // On a phone the shell keeps this entry itself, in its app drawer.
      SettingsSection {
        visible: !root.app.compact && root.app.launcher.active
        app: root.app
        width: body.width
        title: "App launcher"
        note: "Airwaves has an entry in Omarchy's app menu, so you can open it by name. The entry is the file ~/.local/share/applications/omarchy-plugin-io.github.simonschubert.airwaves.desktop."
        Row {
          spacing: 6
          Chip { app: root.app; text: "Show"; selected: root.app.store.prefs.launcher !== false; onClicked: root.app.launcher.setShown(true) }
          Chip { app: root.app; text: "Hide"; selected: root.app.store.prefs.launcher === false; onClicked: root.app.launcher.setShown(false) }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "Saved data"
        note: "Lists and logos are kept on disk so the app opens instantly and works offline. Favourites and history are only ever on this computer."
        Flow {
          width: parent.width
          spacing: 6
          Chip {
            app: root.app
            glyph: G.refresh
            text: "Clear saved lists"
            onClicked: { root.app.api.clear(); root.app.store.clearSnapshot(); root.app.refresh(true); root.app.toast("Saved lists cleared") }
          }
          Chip {
            app: root.app
            glyph: G.remove
            text: root.confirmClear ? "Tap again to clear" : "Clear history"
            tint: root.app.ui.down
            selected: root.confirmClear
            onClicked: {
              if (!root.confirmClear) { root.confirmClear = true; confirmTimer.restart(); return }
              root.confirmClear = false
              root.app.store.clearRecent()
              root.app.toast("History cleared")
            }
          }
        }
      }

      SettingsSection {
        visible: !root.app.compact
        app: root.app
        width: body.width
        title: "Keys"
        note: "Space plays or stops · 1–4 switch tabs · / searches · f stars the station · n opens Now Playing · + and − change the volume, m mutes · Esc goes back"
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "About"
        note: "Airwaves " + root.app.version
          + ". Stations from radio-browser.info, a free directory that anybody can add a station to. Airwaves is an independent app, not affiliated with radio-browser.info or with any station."
        Row {
          spacing: 6
          Chip { app: root.app; glyph: G.open; text: "radio-browser.info"; onClicked: root.app.openLink(Api.SITE) }
          Chip { app: root.app; glyph: G.web; text: "Source"; onClicked: root.app.openLink("https://github.com/SimonSchubert/moarchy-apps/tree/main/apps/airwaves") }
        }
      }
    }
  }
}
