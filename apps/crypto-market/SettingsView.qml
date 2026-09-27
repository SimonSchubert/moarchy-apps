import QtQuick
import "Api.mjs" as Api

// Currency, how much to load and how often, and an optional CoinGecko key.
Item {
  id: root
  property var app

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
        title: "Currency"
        note: "Prices, market caps and your portfolio are shown in this currency."
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: Api.CURRENCIES
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData.code.toUpperCase()
              selected: root.app.currency === modelData.code
              onClicked: root.app.store.set("currency", modelData.code)
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "Markets list"
        note: "How many coins the Markets tab loads, by market cap. Longer lists take more requests."
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: [100, 250, 500, 1000]
            delegate: Chip {
              required property int modelData
              app: root.app
              text: "Top " + modelData
              selected: root.app.store.topN === modelData
              onClicked: root.app.store.set("topN", modelData)
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "Refresh prices every"
        note: "Only while the app is open. CoinGecko updates its free prices about once a minute."
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: [{ s: 60, l: "1 min" }, { s: 120, l: "2 min" }, { s: 300, l: "5 min" }, { s: 900, l: "15 min" }]
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData.l
              selected: root.app.store.refreshSec === modelData.s
              onClicked: root.app.store.set("refreshSec", modelData.s)
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "CoinGecko Demo API key"
        note: "Optional. The free public API allows only a few requests a minute; a free Demo key from coingecko.com/en/developers/dashboard raises that to 30. The key stays on this computer and is sent only to CoinGecko."
        Field {
          id: keyField
          width: parent.width
          app: root.app
          numeric: false
          placeholder: "CG-…"
          text: root.app.store.apiKey
          input.echoMode: input.activeFocus ? TextInput.Normal : TextInput.Password
          onEdited: function (t) { saveKey.restart() }
          onAccepted: saveKey.triggered()
          Timer {
            id: saveKey
            interval: 800
            onTriggered: root.app.store.set("apiKey", keyField.text.trim().replace(/[^A-Za-z0-9_-]/g, "").slice(0, 80))
          }
        }
      }

      // On a phone the shell keeps this entry itself, in its app drawer.
      SettingsSection {
        visible: !root.app.compact && root.app.launcher.active
        app: root.app
        width: body.width
        title: "App launcher"
        note: "Crypto Market has an entry in Omarchy's app menu, so you can open it by name. The entry is the file ~/.local/share/applications/omarchy-plugin-io.github.simonschubert.crypto-market.desktop."
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
        note: "Prices are kept on disk so the app opens instantly and works offline. Your watchlist and portfolio are not touched."
        Chip {
          app: root.app
          text: "Clear saved prices"
          onClicked: { root.app.gecko.clear(); root.app.store.clearSnapshot(); root.app.refresh(true) }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "About"
        note: "Crypto Market " + (root.app.manifest && root.app.manifest.version ? root.app.manifest.version : "")
          + ". Market data provided by CoinGecko (coingecko.com). Not financial advice."
        Chip {
          app: root.app
          text: "CoinGecko ↗"
          onClicked: Qt.openUrlExternally("https://www.coingecko.com")
        }
      }
    }
  }
}
