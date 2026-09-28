import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Address.js" as Address
import "Compose.js" as Compose
import "Glyphs.js" as G

// Writing: To, Cc and Bcc with names from Contacts under whichever one has
// the caret, a subject, and the text, which takes the rest of the height.
// Back keeps what was written as a draft; the bin throws it away, after
// asking; Send, or Ctrl+Enter, sends it.
Item {
  id: root
  property var app
  property bool paged: false
  property bool showCc: false

  // Which address field has the caret, and who in Contacts could be what is
  // being typed into it.
  readonly property var addressField: toField.input.activeFocus ? toField
    : ccField.input.activeFocus ? ccField
    : bccField.input.activeFocus ? bccField : null
  readonly property var suggestions: addressField ? Address.matching(app.people, addressField.text, 5) : []

  // The form, filled from a draft. The caret goes where writing starts: To
  // for a new message, above the quote for a reply.
  function load(draft) {
    toField.text = draft.to
    ccField.text = draft.cc
    bccField.text = draft.bcc
    subjectField.text = draft.subject
    body.text = draft.text
    showCc = draft.cc.length > 0 || draft.bcc.length > 0
    Qt.callLater(function () {
      if (!draft.to.length) toField.takeFocus()
      else {
        body.edit.cursorPosition = 0
        body.edit.forceActiveFocus()
      }
    })
  }

  function typed() {
    return Compose.withFields(app.compose, {
      to: toField.text, cc: ccField.text, bcc: bccField.text,
      subject: subjectField.text, text: body.text, error: ""
    })
  }

  function focusTo() {
    toField.takeFocus()
    toField.input.cursorPosition = toField.text.length
  }

  function pick(p) {
    var field = addressField || toField
    field.text = Address.replaceLastToken(field.text, p)
    field.takeFocus()
    field.input.cursorPosition = field.text.length
  }

  Component.onCompleted: {
    app.composeView = root
    load(app.compose)
  }
  Component.onDestruction: if (app.composeView === root) app.composeView = null
  Connections {
    target: root.app
    function onComposeRevisionChanged() { root.load(root.app.compose) }
  }

  Shortcut {
    sequences: ["Ctrl+Return", "Ctrl+Enter"]
    onActivated: root.app.send(false)
  }

  // The top: a way back or out, the bin, and Send.
  Item {
    id: bar
    width: parent.width
    height: root.app.compact ? 60 : 56

    IconButton {
      id: backButton
      visible: root.paged
      x: 4
      anchors.verticalCenter: parent.verticalCenter
      width: visible ? implicitWidth : 0
      app: root.app
      glyph: KG.back
      label: "Back"
      onClicked: root.app.back()
    }
    Text {
      anchors.left: backButton.right
      anchors.leftMargin: root.paged ? 4 : 20
      anchors.right: actions.left
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      text: Compose.title(root.app.compose)
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.Bold
      font.capitalization: Font.AllUppercase
      font.letterSpacing: root.app.ui.tracking
      elide: Text.ElideRight
    }
    Row {
      id: actions
      anchors.right: parent.right
      anchors.rightMargin: root.paged ? 8 : 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4
      IconButton {
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        glyph: G.trash
        label: "Throw away"
        onClicked: root.app.discardCompose()
      }
      IconButton {
        visible: !root.paged
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        glyph: KG.close
        label: "Keep as a draft and close"
        onClicked: root.app.leaveCompose()
      }
      Button {
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        primary: true
        glyph: G.send
        text: "Send"
        onClicked: root.app.send(false)
      }
    }
  }

  Column {
    id: fields
    anchors.top: bar.bottom
    x: root.paged ? root.app.ui.gutter : 20
    width: Math.min(parent.width - x * 2, 820)
    spacing: 10

    Rectangle {
      visible: root.app.compose.error.length > 0
      width: parent.width
      height: visible ? errorText.implicitHeight + 20 : 0
      radius: root.app.ui.radius
      color: root.app.ui.alpha(root.app.ui.unsent, 0.14)
      Text {
        id: errorText
        x: 12
        y: 10
        width: parent.width - 24
        wrapMode: Text.Wrap
        text: "Not sent: " + root.app.compose.error
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
    }

    // To, Cc and Bcc, in front of their fields: filled in, three boxes of
    // addresses are otherwise three boxes nobody can tell apart.
    Row {
      width: parent.width
      spacing: 8
      FieldLabel { app: root.app; text: "To" }
      TextField {
        id: toField
        width: parent.width - 66 - (ccButton.visible ? ccButton.width + 8 : 0)
        app: root.app
        placeholder: "Name or address"
        inputHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
        onAccepted: subjectField.takeFocus()
      }
      Chip {
        id: ccButton
        visible: !root.showCc
        anchors.bottom: parent.bottom
        app: root.app
        text: "Cc"
        onClicked: { root.showCc = true; Qt.callLater(ccField.takeFocus) }
      }
    }
    Row {
      visible: root.showCc
      width: parent.width
      spacing: 8
      FieldLabel { app: root.app; text: "Cc" }
      TextField {
        id: ccField
        width: parent.width - 66
        app: root.app
        placeholder: "Name or address"
        inputHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
      }
    }
    Row {
      visible: root.showCc
      width: parent.width
      spacing: 8
      FieldLabel { app: root.app; text: "Bcc" }
      TextField {
        id: bccField
        width: parent.width - 66
        app: root.app
        placeholder: "Seen by nobody else"
        inputHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
      }
    }

    // Names from Contacts, under whichever address field has the caret.
    Column {
      visible: root.suggestions.length > 0
      width: parent.width
      Repeater {
        model: root.suggestions
        delegate: ListRow {
          id: suggestion
          required property var modelData
          x: 66
          width: fields.width - 66
          app: root.app
          glyph: G.account
          title: Address.label(modelData)
          text: modelData.name ? modelData.email : ""
          onClicked: root.pick(suggestion.modelData)
        }
      }
    }

    Row {
      width: parent.width
      spacing: 8
      FieldLabel { app: root.app; text: "Subject" }
      TextField {
        id: subjectField
        width: parent.width - 66
        app: root.app
        onAccepted: body.edit.forceActiveFocus()
      }
    }

    // What a forward carries with it.
    Repeater {
      model: root.app.compose.attachments
      delegate: Row {
        required property var modelData
        spacing: 6
        Icon { app: root.app; text: G.attachment; size: 14; color: root.app.ui.muted }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: modelData
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }
    }
  }

  TextArea {
    id: body
    anchors.top: fields.bottom
    anchors.topMargin: 10
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 12 + (root.paged ? root.app.bottomInset : 0)
    x: fields.x
    width: fields.width
    app: root.app
    placeholder: "Write your message"
  }
}
