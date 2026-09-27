import QtQuick
import Quickshell
import "Api.mjs" as Api
import "Glyphs.js" as G

// Your Trakt account, spoilers, the app menu entry, and which Trakt app to
// sign in as.
Item {
  id: root
  property var app

  readonly property var trakt: app.trakt
  readonly property var user: app.store.user
  readonly property string statsUrl: user && user.slug ? Api.statsUrl(user.slug) : ""
  readonly property var stats: { trakt.revision; return statsUrl ? trakt.peek(statsUrl) : null }
  property bool confirmSignOut: false

  function refresh(force) {
    if (trakt.signedIn) trakt.want(Api.settingsUrl(), "settings", force ? 0 : 3600000, false)
    if (statsUrl) trakt.want(statsUrl, "stats", force ? 0 : 600000, false)
  }
  onStatsUrlChanged: refresh(false)

  Timer { id: confirmTimer; interval: 3000; onTriggered: root.confirmSignOut = false }
  // The code's countdown.
  Timer { interval: 1000; repeat: true; running: root.visible && root.trakt.authState === "code"; onTriggered: root.app.clock = Date.now() }

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

      // ------------------------------------------------ account
      Rectangle {
        width: parent.width
        height: account.implicitHeight + 40
        radius: root.app.ui.radius + 4
        color: root.app.ui.surface
        border.width: 1
        border.color: root.app.ui.divider

        Column {
          id: account
          x: 20
          y: 20
          width: parent.width - 40
          spacing: 14

          // Signed in.
          Row {
            visible: root.trakt.signedIn
            width: parent.width
            spacing: 14
            Avatar {
              app: root.app
              size: 60
              source: root.user ? root.user.avatar || "" : ""
              name: root.user ? root.user.username || "" : ""
              ground: root.app.ui.surface
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - 74
              spacing: 2
              Row {
                spacing: 8
                Text {
                  text: root.user ? root.user.name || root.user.username : "Signed in"
                  color: root.app.ui.text
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.lg
                  font.weight: Font.Bold
                }
                Rectangle {
                  visible: !!(root.user && root.user.vip)
                  anchors.verticalCenter: parent.verticalCenter
                  width: 36
                  height: 18
                  radius: 9
                  color: root.app.ui.heart
                  Text { anchors.centerIn: parent; text: "VIP"; color: "white"; font.pixelSize: 10; font.weight: Font.Bold; font.family: root.app.ui.font }
                }
              }
              Text {
                width: parent.width
                elide: Text.ElideRight
                text: root.user ? "@" + root.user.username : ""
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
              }
            }
          }

          // What you have watched, in numbers.
          Row {
            visible: root.trakt.signedIn && root.stats !== null
            width: parent.width
            spacing: 8
            Repeater {
              model: root.stats ? [
                { v: Api.group(root.stats.movies || 0), l: "movies" },
                { v: Api.group(root.stats.episodes || 0), l: "episodes" },
                { v: Api.group(Math.round(((root.stats.movieMinutes || 0) + (root.stats.episodeMinutes || 0)) / 60)), l: "hours" }
              ] : []
              delegate: Rectangle {
                required property var modelData
                width: (account.width - 16) / 3
                height: 58
                radius: root.app.ui.radius
                color: root.app.ui.bg
                Column {
                  anchors.centerIn: parent
                  spacing: 1
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.v
                    color: root.app.ui.text
                    font.family: root.app.ui.font
                    font.pixelSize: root.app.ui.fs.lg
                    font.weight: Font.Bold
                    font.features: ({ "tnum": 1 })
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.l
                    color: root.app.ui.muted
                    font.family: root.app.ui.font
                    font.pixelSize: root.app.ui.fs.xs
                  }
                }
              }
            }
          }

          Flow {
            visible: root.trakt.signedIn
            width: parent.width
            spacing: 8
            Button {
              app: root.app
              glyph: G.open
              text: "Profile on Trakt"
              onClicked: if (root.user && root.user.slug) Qt.openUrlExternally(Api.SITE + "/users/" + root.user.slug)
            }
            Button {
              app: root.app
              glyph: G.logout
              text: root.confirmSignOut ? "Tap again to sign out" : "Sign out"
              tint: root.app.ui.heart
              active: root.confirmSignOut
              onClicked: {
                if (!root.confirmSignOut) { root.confirmSignOut = true; confirmTimer.restart(); return }
                root.confirmSignOut = false
                root.trakt.signOut()
                root.app.toast("Signed out")
              }
            }
          }

          // Signed out: the device flow, step by step.
          Row {
            visible: !root.trakt.signedIn && root.trakt.authState !== "code"
            width: parent.width
            spacing: 14
            Mark { size: 48; anchors.verticalCenter: parent.verticalCenter }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - 62
              spacing: 3
              Text {
                text: "Sign in with Trakt"
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.lg
                font.weight: Font.Bold
              }
              Text {
                width: parent.width
                text: "Your watchlist, up next, calendar, history and ratings, kept in step with every other Trakt app you use."
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
                wrapMode: Text.Wrap
              }
            }
          }
          Text {
            visible: !root.trakt.signedIn && root.trakt.authState === "failed"
            width: parent.width
            text: root.trakt.authMessage
            color: root.app.ui.heart
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            wrapMode: Text.Wrap
          }
          Row {
            visible: !root.trakt.signedIn && root.trakt.authState !== "code"
            spacing: 10
            Button {
              app: root.app
              primary: true
              glyph: G.login
              enabled: root.trakt.authState !== "asking"
              text: root.trakt.authState === "asking" ? "Getting a code…" : root.trakt.authState === "failed" ? "Try again" : "Sign in"
              onClicked: root.trakt.beginSignIn()
            }
          }

          Column {
            visible: !root.trakt.signedIn && root.trakt.authState === "code"
            width: parent.width
            spacing: 14
            Text {
              width: parent.width
              text: "On any phone or computer, go to trakt.tv/activate and enter this code:"
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
              wrapMode: Text.Wrap
            }
            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              width: code.implicitWidth + 48
              height: 72
              radius: root.app.ui.radius + 2
              color: root.app.ui.bg
              border.width: 2
              border.color: root.app.ui.accent
              Text {
                id: code
                anchors.centerIn: parent
                text: root.trakt.userCode
                color: root.app.ui.text
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 34
                font.weight: Font.Bold
                font.letterSpacing: 6
              }
            }
            Flow {
              width: parent.width
              spacing: 8
              Button {
                app: root.app
                primary: true
                glyph: G.open
                text: "Open trakt.tv/activate"
                onClicked: Qt.openUrlExternally(root.trakt.verifyUrl)
              }
              Button {
                app: root.app
                glyph: G.copy
                text: "Copy code"
                onClicked: { Quickshell.clipboardText = root.trakt.userCode; root.app.toast("Code copied") }
              }
              Button {
                app: root.app
                text: "Cancel"
                onClicked: root.trakt.cancelSignIn()
              }
            }
            Row {
              spacing: 10
              Spinner { app: root.app; size: 18; running: root.visible && root.trakt.authState === "code"; anchors.verticalCenter: parent.verticalCenter }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: account.width - 28
                wrapMode: Text.Wrap
                text: {
                  var s = Math.max(0, Math.round((root.trakt.codeExpires - root.app.clock) / 1000))
                  return "Waiting for you to approve · code valid for " + Math.floor(s / 60) + ":" + ("0" + s % 60).slice(-2)
                }
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xs
              }
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "Spoilers"
        note: "Hide the titles, stills and stories of episodes you haven't watched yet."
        Row {
          spacing: 6
          Chip { app: root.app; glyph: G.eye; text: "Show"; selected: root.app.store.prefs.hideSpoilers !== true; onClicked: root.app.store.set("hideSpoilers", false) }
          Chip { app: root.app; glyph: G.eyeOff; text: "Hide"; selected: root.app.store.prefs.hideSpoilers === true; onClicked: root.app.store.set("hideSpoilers", true) }
        }
      }

      // On a phone the shell keeps this entry itself, in its app drawer.
      SettingsSection {
        visible: !root.app.compact
        app: root.app
        width: body.width
        title: "App launcher"
        note: "Couch has an entry in Omarchy's app menu, so you can open it by name. The entry is the file ~/.local/share/applications/omarchy-plugin-io.github.simonschubert.couch.desktop."
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
        note: "Lists and pictures are kept on disk so the app opens instantly and works offline. Your account is not touched."
        Chip {
          app: root.app
          glyph: G.refresh
          text: "Clear saved lists"
          onClicked: { root.app.trakt.clear(); root.app.store.clearSnapshot(); root.app.refresh(true); root.app.toast("Saved lists cleared") }
        }
      }

      SettingsSection {
        id: appSection
        app: root.app
        width: body.width
        title: "Trakt app"
        note: "Optional. Couch signs in as its own Trakt app. To use one of yours instead, create it at trakt.tv/oauth/applications with the redirect URI urn:ietf:wg:oauth:2.0:oob and paste its client ID and secret here. Changing this signs you out."
        property bool open: root.app.store.clientId !== "" || !root.app.trakt.configured
        Chip {
          visible: !appSection.open
          app: root.app
          text: "Use my own app"
          onClicked: appSection.open = true
        }
        Column {
          visible: appSection.open
          width: parent.width
          spacing: 10
          Field {
            id: idField
            width: parent.width
            app: root.app
            numeric: false
            label: "Client ID"
            placeholder: "From your app's page on trakt.tv"
            text: root.app.store.clientId
            valid: text === "" || /^[A-Za-z0-9_-]{20,128}$/.test(text.trim())
          }
          Field {
            id: secretField
            width: parent.width
            app: root.app
            numeric: false
            label: "Client secret"
            placeholder: "From your app's page on trakt.tv"
            text: root.app.store.clientSecret
            input.echoMode: input.activeFocus ? TextInput.Normal : TextInput.Password
            valid: text === "" || /^[A-Za-z0-9_-]{20,128}$/.test(text.trim())
          }
          Row {
            spacing: 8
            Button {
              app: root.app
              primary: true
              text: "Save"
              enabled: idField.valid && secretField.valid && (idField.text.trim() === "") === (secretField.text.trim() === "")
              onClicked: {
                var id = idField.text.trim(), secret = secretField.text.trim()
                if (id === root.app.store.clientId && secret === root.app.store.clientSecret) return
                if (root.trakt.signedIn) root.trakt.signOut()
                root.app.store.set("clientId", id)
                root.app.store.set("clientSecret", secret)
                root.app.trakt.clear()
                root.app.resetFocus()
                root.app.toast(id ? "Using your Trakt app" : "Using the built-in Trakt app")
                Qt.callLater(root.app.refresh, true)
              }
            }
            Button {
              visible: root.app.store.clientId !== ""
              app: root.app
              text: "Use the built-in app"
              onClicked: { idField.text = ""; secretField.text = "" }
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: body.width
        title: "About"
        note: "Couch for Trakt " + (root.app.manifest && root.app.manifest.version ? root.app.manifest.version : "")
          + ". Movie and show data and images from Trakt (trakt.tv). Couch is an independent app and not affiliated with or endorsed by Trakt."
        Row {
          spacing: 6
          Chip { app: root.app; glyph: G.open; text: "trakt.tv"; onClicked: Qt.openUrlExternally(Api.SITE) }
          Chip { app: root.app; glyph: G.web; text: "Source"; onClicked: Qt.openUrlExternally("https://github.com/SimonSchubert/omarchy-couch") }
        }
      }
    }
  }
}
