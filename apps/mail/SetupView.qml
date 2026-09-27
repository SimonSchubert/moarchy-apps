import QtQuick
import "kit"
import "Store.js" as MailStore

// Signing in: a name, an address and a password, and the servers found for
// that address -- shown, so they can be changed, and never written over once
// somebody has typed in them.
Item {
  id: root
  property var app
  property bool paged: false

  property bool showServers: false
  // True while the form is being filled in by code, so that what autoconfig
  // wrote is not taken for somebody's typing.
  property bool filling: false
  property bool serversEdited: false
  property string imapSecurity: "tls"
  property string smtpSecurity: "tls"

  function fill(a) {
    filling = true
    serversEdited = !!a
    showServers = !!a
    nameField.text = a ? a.name : ""
    emailField.text = a ? a.email : ""
    passwordField.text = ""
    usernameField.text = a ? a.username : ""
    imapHostField.text = a ? a.imap.host : ""
    imapPortField.text = a ? String(a.imap.port) : ""
    smtpHostField.text = a ? a.smtp.host : ""
    smtpPortField.text = a ? String(a.smtp.port) : ""
    imapSecurity = a ? a.imap.security : "tls"
    smtpSecurity = a ? a.smtp.security : "tls"
    filling = false
  }

  function type(name, email, password) {
    filling = true
    nameField.text = name
    emailField.text = email
    passwordField.text = password
    filling = false
  }

  function emailTyped() {
    if (filling || serversEdited) return
    autoconfigTimer.restart()
  }

  function serverTyped() { if (!filling) serversEdited = true }

  function lookUpServers() {
    var email = emailField.text.trim()
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(email) || serversEdited) return
    app.run("autoconfig", { email: email }, "read", { email: email }, false)
  }

  // Whether the servers were filled in: not for an address that has been
  // changed since it was asked about, and never over what somebody typed.
  function applyServers(email, answer) {
    if (serversEdited || email !== emailField.text.trim()) return false
    filling = true
    imapHostField.text = answer.imap.host
    imapPortField.text = String(answer.imap.port)
    imapSecurity = answer.imap.security
    smtpHostField.text = answer.smtp.host
    smtpPortField.text = String(answer.smtp.port)
    smtpSecurity = answer.smtp.security
    usernameField.text = answer.username
    filling = false
    return true
  }

  function request() {
    var email = emailField.text.trim()
    return {
      name: nameField.text.trim(), email: email, password: passwordField.text,
      username: usernameField.text.trim() || email,
      imap: { host: imapHostField.text.trim(), port: parseInt(imapPortField.text, 10) || 0, security: imapSecurity },
      smtp: { host: smtpHostField.text.trim(), port: parseInt(smtpPortField.text, 10) || 0, security: smtpSecurity }
    }
  }

  Component.onCompleted: {
    app.setupView = root
    fill(app.editingAccount ? app.account : null)
  }
  Component.onDestruction: if (app.setupView === root) app.setupView = null

  Timer {
    id: autoconfigTimer
    interval: 900
    onTriggered: root.lookUpServers()
  }

  PageHeader {
    id: head
    visible: root.paged
    height: visible ? implicitHeight : 0
    width: parent.width
    app: root.app
    title: root.app.editingAccount ? "Account" : "Sign in"
  }

  Flickable {
    id: flick
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: col.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: col
      x: root.app.compact ? 16 : 26
      y: 8
      width: Math.min(flick.width - x * 2, 560)
      spacing: 20

      SettingsSection {
        app: root.app
        width: parent.width
        title: "Your account"
        note: "The password stays on this computer, in a file only you can read, and goes to nobody but the servers below."
        TextField {
          id: nameField
          width: parent.width
          app: root.app
          placeholder: "Your name, as people see it"
          onAccepted: emailField.takeFocus()
        }
        TextField {
          id: emailField
          width: parent.width
          app: root.app
          placeholder: "Email address"
          inputHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
          onTextChanged: root.emailTyped()
          onAccepted: passwordField.takeFocus()
        }
        TextField {
          id: passwordField
          width: parent.width
          app: root.app
          placeholder: root.app.editingAccount ? "Password (leave empty to keep it)" : "Password"
          echoMode: TextInput.Password
          inputHints: Qt.ImhHiddenText | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
          onAccepted: root.app.signIn()
        }
      }

      Rectangle {
        visible: root.app.setupNote.length > 0
        width: parent.width
        height: visible ? noteText.implicitHeight + 24 : 0
        radius: root.app.ui.radius
        color: root.app.ui.alpha(root.app.ui.warn, 0.16)
        Text {
          id: noteText
          x: 12
          y: 12
          width: parent.width - 24
          wrapMode: Text.Wrap
          text: root.app.setupNote
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }

      SettingsSection {
        visible: root.showServers || imapHostField.text.length > 0
        app: root.app
        width: parent.width
        title: "Servers"

        // The summary, until somebody wants to change it.
        Item {
          visible: !root.showServers
          width: parent.width
          height: visible ? summary.implicitHeight : 0
          Column {
            id: summary
            width: parent.width - change.width - 12
            spacing: 2
            Text {
              width: parent.width
              text: imapHostField.text
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
              elide: Text.ElideMiddle
            }
            Text {
              text: "Incoming · " + imapPortField.text + " · " + MailStore.securityLabel(root.imapSecurity)
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
            Item { width: 1; height: 6 }
            Text {
              width: parent.width
              text: smtpHostField.text
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
              elide: Text.ElideMiddle
            }
            Text {
              text: "Outgoing · " + smtpPortField.text + " · " + MailStore.securityLabel(root.smtpSecurity)
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
            }
          }
          Button {
            id: change
            anchors.right: parent.right
            app: root.app
            text: "Change"
            onClicked: root.showServers = true
          }
        }

        Column {
          visible: root.showServers
          width: parent.width
          spacing: 10
          Row {
            width: parent.width
            spacing: 8
            TextField {
              id: imapHostField
              width: parent.width - 96
              app: root.app
              label: "Incoming (IMAP)"
              placeholder: "imap.example.org"
              inputHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
              onTextChanged: root.serverTyped()
            }
            TextField {
              id: imapPortField
              width: 88
              app: root.app
              label: "Port"
              placeholder: "993"
              inputHints: Qt.ImhDigitsOnly
              onTextChanged: root.serverTyped()
            }
          }
          Flow {
            width: parent.width
            spacing: 6
            Repeater {
              model: ["tls", "starttls", "none"]
              delegate: Chip {
                required property string modelData
                app: root.app
                text: MailStore.securityLabel(modelData)
                selected: root.imapSecurity === modelData
                onClicked: { root.imapSecurity = modelData; root.serverTyped() }
              }
            }
          }
          Row {
            width: parent.width
            spacing: 8
            TextField {
              id: smtpHostField
              width: parent.width - 96
              app: root.app
              label: "Outgoing (SMTP)"
              placeholder: "smtp.example.org"
              inputHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
              onTextChanged: root.serverTyped()
            }
            TextField {
              id: smtpPortField
              width: 88
              app: root.app
              label: "Port"
              placeholder: "465"
              inputHints: Qt.ImhDigitsOnly
              onTextChanged: root.serverTyped()
            }
          }
          Flow {
            width: parent.width
            spacing: 6
            Repeater {
              model: ["tls", "starttls", "none"]
              delegate: Chip {
                required property string modelData
                app: root.app
                text: MailStore.securityLabel(modelData)
                selected: root.smtpSecurity === modelData
                onClicked: { root.smtpSecurity = modelData; root.serverTyped() }
              }
            }
          }
          TextField {
            id: usernameField
            width: parent.width
            app: root.app
            label: "User name"
            placeholder: "If it is not the address"
            inputHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onTextChanged: root.serverTyped()
          }
        }
      }

      Rectangle {
        visible: root.app.setupError.length > 0
        width: parent.width
        height: visible ? errorText.implicitHeight + 24 : 0
        radius: root.app.ui.radius
        color: root.app.ui.alpha(root.app.ui.bad, 0.14)
        Text {
          id: errorText
          x: 12
          y: 12
          width: parent.width - 24
          wrapMode: Text.Wrap
          text: root.app.setupError
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
        }
      }

      Row {
        width: parent.width
        spacing: 10
        Button {
          width: cancel.visible ? parent.width - cancel.width - 10 : parent.width
          app: root.app
          primary: true
          text: root.app.signingIn ? "Signing in…" : root.app.editingAccount ? "Save" : "Sign in"
          enabled: !root.app.signingIn
          onClicked: root.app.signIn()
        }
        Button {
          id: cancel
          visible: root.app.account !== null && !root.paged
          app: root.app
          text: "Cancel"
          onClicked: root.app.back()
        }
      }
    }
  }
}
