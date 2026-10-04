import QtQuick
import "kit"
import "Otp.js" as Otp

// An account, as a page over the list. Two shapes:
//
// **Adding** is one box that takes whatever a site gave you -- the key printed
// under its QR code, the otpauth:// link inside it, several links, or Google
// Authenticator's whole export -- and works out which it was as you type. A
// single key shows its code before it is saved, which is the check that
// matters: the site asks for one to confirm, and a typo in the key shows up
// here rather than as a code the site refuses.
//
// **Editing** is the labels, and the key behind a button, for moving the
// account to another device. The key itself is never edited: a changed key
// is a different account.
Item {
  id: root
  property var app

  readonly property var draft: app.draft
  readonly property bool isNew: app.draftIsNew

  // What the box holds, read.
  readonly property var reading: isNew ? Otp.read(keyBox.text, 1) : ({ kind: "none", accounts: [], errors: [] })
  readonly property bool many: reading.kind === "links" && reading.accounts.length > 1
  // The account the form describes, or null.
  readonly property var single: {
    if (!isNew) return draft
    var base = reading.kind === "key" ? { secret: keyBox.text }
      : reading.kind === "links" && reading.accounts.length === 1 ? reading.accounts[0] : null
    if (!base) return null
    return Otp.normalise({ secret: base.secret, issuer: issuerField.text, name: nameField.text,
                           algorithm: algorithm, digits: digits, period: Number(periodField.text) || Otp.DEFAULT_PERIOD }, 1)
  }
  readonly property bool canSave: isNew ? (many || single !== null) : true

  property string algorithm: "SHA1"
  property int digits: 6
  property bool advanced: false
  property bool showKey: false

  // A link fills the form in, once per link, and leaves it to be corrected.
  property string filledFrom: ""
  onReadingChanged: {
    if (!isNew || reading.kind !== "links" || reading.accounts.length !== 1) return
    var a = reading.accounts[0]
    if (filledFrom === a.secret) return
    filledFrom = a.secret
    issuerField.text = a.issuer
    nameField.text = a.name
    algorithm = a.algorithm
    digits = a.digits
    periodField.text = String(a.period)
    advanced = advanced || Otp.details(a) !== ""
  }

  function load() {
    showKey = false
    filledFrom = ""
    if (!draft) return
    issuerField.text = draft.issuer || ""
    nameField.text = draft.name || ""
    algorithm = draft.algorithm || "SHA1"
    digits = draft.digits || 6
    periodField.text = String(draft.period || Otp.DEFAULT_PERIOD)
    advanced = false
    flick.contentY = 0
    // Last: a link in it fills the fields above in.
    keyBox.text = isNew ? (app.pendingText || "") : ""
    app.pendingText = ""
  }
  Component.onCompleted: load()

  // A scan or a paste lands in the box.
  Connections {
    target: root.app
    function onDropText(text) { keyBox.text = text }
  }

  function save() {
    if (!canSave) return
    if (!isNew) {
      app.saveLabels(draft.id, issuerField.text, nameField.text)
    } else if (many) {
      app.addAll(reading.accounts)
    } else {
      app.addAll([single])
    }
  }

  readonly property int remaining: single ? Otp.remainingAt(app.now, single.period) : 30
  readonly property string code: single ? Otp.codeFor(single, Otp.counterAt(app.now, single.period)) : ""

  // The code the form describes, big, with its ring: a tap copies it once the
  // account is saved.
  component CodeCard: Rectangle {
    width: form.width
    height: 92
    radius: root.app.ui.radius
    color: root.app.ui.surface
    border.width: 1
    border.color: root.app.ui.line
    Column {
      x: 16
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - 80
      spacing: 2
      Text {
        text: root.isNew ? "The code the site asks for" : "Code now · tap to copy"
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: root.app.ui.tracking
        width: parent.width
        elide: Text.ElideRight
      }
      Text {
        text: Otp.grouped(root.code)
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xxl
        font.weight: Font.Bold
        font.letterSpacing: 2
      }
    }
    Ring {
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      size: 36
      remaining: root.remaining
      period: root.single ? root.single.period : 30
    }
    MouseArea {
      anchors.fill: parent
      enabled: !root.isNew
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.app.copyCode(root.draft.id)
    }
      }

  PageHeader {
    id: head
    width: parent.width
    app: root.app
    title: root.isNew ? "Add an account" : "Account"
    IconButton {
      visible: !root.isNew
      app: root.app
      glyph: root.app.glyphs.remove
      label: "Delete this account"
      onClicked: root.app.askDelete(root.draft.id)
    }
    IconButton {
      app: root.app
      glyph: root.app.glyphs.check
      color: root.canSave ? root.app.ui.accent : root.app.ui.muted
      label: root.isNew ? "Add" : "Save"
      onClicked: root.save()
    }
  }

  Flickable {
    id: flick
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: form.implicitHeight + 40 + root.app.bottomInset
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: form
      x: Math.max(root.app.ui.gutter + 4, (flick.width - width) / 2)
      y: 8
      width: Math.min(flick.width - (root.app.ui.gutter + 4) * 2, 560)
      spacing: 16

      CodeCard { visible: !root.isNew && root.code !== "" }

      // ------------------------------------------------ the key (adding)

      Column {
        visible: root.isNew
        width: parent.width
        spacing: 8
        Text {
          width: parent.width
          text: "The site shows a QR code and, under it, a key to type in by hand. Paste the key, or the link the QR code holds — or a Google Authenticator export."
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          wrapMode: Text.Wrap
        }
        TextArea {
          id: keyBox
          width: parent.width
          implicitHeight: 92
          app: root.app
          placeholder: "JBSW Y3DP EHPK 3PXP  or  otpauth://totp/..."
        }
        Text {
          width: parent.width
          visible: text !== ""
          text: root.many ? root.reading.accounts.length + " accounts in this text" + (root.reading.errors.length ? " — " + root.reading.errors.join("; ") : "")
            : root.reading.kind === "links" && root.reading.accounts.length === 1 ? "Read from the link. Check the names."
            : root.reading.errors.join("; ")
          color: root.reading.accounts.length || root.reading.kind === "key" ? root.app.ui.good : root.app.ui.bad
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          wrapMode: Text.Wrap
        }
        Flow {
          width: parent.width
          spacing: 8
          Button {
            app: root.app
            glyph: root.app.glyphs.paste
            text: "Paste"
            onClicked: root.app.pasteKey()
          }
          Button {
            visible: root.app.canScan && !root.app.compact
            app: root.app
            glyph: root.app.glyphs.scan
            text: root.app.scanning ? "Drag round the QR code" : "Scan the screen"
            onClicked: root.app.scanScreen()
          }
        }
      }

      CodeCard { visible: root.isNew && root.single !== null && root.code !== "" }

      // ------------------------------------------------ the list (several)

      Column {
        visible: root.many
        width: parent.width
        spacing: 4
        Repeater {
          model: root.many ? root.reading.accounts : []
          delegate: Text {
            required property var modelData
            width: form.width
            text: Otp.title(modelData) + (modelData.issuer ? "  " + modelData.name : "")
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            elide: Text.ElideRight
          }
        }
      }

      // ------------------------------------------------ the labels

      TextField {
        id: issuerField
        visible: !root.many
        width: parent.width
        app: root.app
        label: "Issuer"
        placeholder: "Who it signs you in to: GitHub, your bank"
        onAccepted: root.save()
      }
      TextField {
        id: nameField
        visible: !root.many
        width: parent.width
        app: root.app
        label: "Account"
        placeholder: "Your user name or email there"
        inputHints: Qt.ImhNoAutoUppercase
        onAccepted: root.save()
      }

      // ------------------------------------------------ advanced (adding)

      Button {
        visible: root.isNew && !root.many && !root.advanced
        app: root.app
        glyph: root.app.glyphs.chevronDown
        text: "Algorithm, digits, period"
        onClicked: root.advanced = true
      }
      Column {
        visible: root.isNew && !root.many && root.advanced
        width: parent.width
        spacing: 12
        Text {
          width: parent.width
          text: "Almost every site uses SHA1, six digits and thirty seconds. Change these only if the site says to."
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          wrapMode: Text.Wrap
        }
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: Otp.ALGORITHMS
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData
              selected: root.algorithm === modelData
              onClicked: root.algorithm = modelData
            }
          }
        }
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: Otp.DIGITS
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData + " digits"
              selected: root.digits === modelData
              onClicked: root.digits = modelData
            }
          }
        }
        TextField {
          id: periodField
          width: 180
          app: root.app
          label: "Seconds a code lasts"
          placeholder: "30"
          inputHints: Qt.ImhDigitsOnly
        }
      }

      // ------------------------------------------------ the key (editing)

      Column {
        visible: !root.isNew && root.draft !== null
        width: parent.width
        spacing: 10
        Text {
          width: parent.width
          text: root.draft ? [root.draft.algorithm, root.draft.digits + " digits", "every " + root.draft.period + " s"].join(" · ") : ""
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
        Button {
          app: root.app
          glyph: root.showKey ? root.app.glyphs.hide : root.app.glyphs.show
          text: root.showKey ? "Hide the key" : "Show the key"
          onClicked: root.showKey = !root.showKey
        }
        Column {
          visible: root.showKey
          width: parent.width
          spacing: 10
          Text {
            width: parent.width
            text: "Anybody with this key has your codes. Type it, or the link, into another authenticator to move this account there."
            color: root.app.ui.warn
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            wrapMode: Text.Wrap
          }
          TextField {
            width: parent.width
            app: root.app
            label: "Key"
            readOnly: true
            text: root.showKey && root.draft ? root.draft.secret.replace(/(.{4})(?=.)/g, "$1 ") : ""
          }
          Button {
            app: root.app
            glyph: root.app.glyphs.link
            text: "Copy the link"
            onClicked: root.app.copyLink(root.draft.id)
          }
        }
      }

      Row {
        spacing: 10
        Button {
          app: root.app
          primary: true
          enabled: root.canSave
          opacity: enabled ? 1 : 0.5
          glyph: root.app.glyphs.check
          text: !root.isNew ? "Save" : root.many ? "Add " + root.reading.accounts.length : "Add"
          onClicked: root.save()
        }
        Button {
          app: root.app
          text: "Cancel"
          onClicked: root.app.closeEditor()
        }
      }
    }
  }
}
