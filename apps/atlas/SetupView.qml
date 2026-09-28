import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Countries.js" as C

// What the atlas says before it has a world to show: that REST Countries
// wants a key now, that one is free, and where to put it. Also what it says
// when the key it had was refused.
//
// Shown only while there is nothing cached. A copy that has the world keeps
// showing it, and the key lives in Settings.
Flickable {
  id: root
  property var app
  // The last thing REST Countries said, if it said no.
  property string trouble: ""
  property bool busy: false

  contentWidth: width
  contentHeight: body.implicitHeight + 40
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  function save() {
    if (root.app.saveKey(field.text)) field.text = ""
  }

  Column {
    id: body
    x: (parent.width - width) / 2
    y: root.app.compact ? 20 : 48
    width: Math.min(parent.width - 40, 460)
    spacing: 16

    Icon {
      anchors.horizontalCenter: parent.horizontalCenter
      app: root.app
      text: G.earth
      size: 52
      color: root.app.ui.accent
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: "Every country, and its flag"
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xl
      font.weight: Font.Bold
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      lineHeight: 1.2
      text: "Atlas reads REST Countries, which asks for a free key. A free account allows 1,000 requests a month; Atlas needs three, once a month, and keeps the world on this device."
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
    }

    Button {
      anchors.horizontalCenter: parent.horizontalCenter
      app: root.app
      glyph: KG.open
      text: "Get a free key"
      onClicked: Qt.openUrlExternally(C.SIGN_UP)
    }

    TextField {
      id: field
      width: parent.width
      app: root.app
      label: "Your key"
      placeholder: "rc_live_…"
      echoMode: TextInput.Password
      inputHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData
      onAccepted: root.save()
    }

    Button {
      width: parent.width
      app: root.app
      primary: true
      glyph: G.key
      text: root.busy ? "Fetching the world…" : "Use this key"
      enabled: !root.busy && field.text.trim() !== ""
      onClicked: root.save()
    }

    Text {
      visible: root.trouble !== ""
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: root.trouble
      color: root.app.ui.bad
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
    }
  }
}
