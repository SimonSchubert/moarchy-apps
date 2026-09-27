import QtQuick
import "kit"
import "Contacts.js" as Contacts

// One person, as a form: a name, a number, an email and a note. A page over
// the list on a phone, the pane beside it on a desktop -- the same four
// fields either way, because a contact is one thing.
//
// It edits the app's draft, a copy. Nothing reaches the file until Save (or
// Enter in a field), and Back leaves the book as it was.
Item {
  id: root
  property var app
  // A page of its own, with a back arrow; otherwise the pane, with a close.
  property bool paged: false

  readonly property var draft: app.draft
  readonly property bool isNew: app.draftIsNew
  readonly property string draftId: draft ? draft.id : ""

  function load() {
    if (!draft) return
    nameField.text = draft.name
    phoneField.text = draft.phone
    emailField.text = draft.email
    noteArea.text = draft.note
    flick.contentY = 0
  }
  onDraftIdChanged: load()
  Component.onCompleted: {
    load()
    if (isNew && !app.compact) Qt.callLater(focusName)
  }

  function focusName() { nameField.takeFocus() }

  function fields() {
    return {
      id: draftId,
      name: String(nameField.text || "").trim(),
      phone: String(phoneField.text || "").trim(),
      email: String(emailField.text || "").trim(),
      note: String(noteArea.text || "").trim()
    }
  }
  function save() { app.commit(fields()) }

  // ------------------------------------------------------------ top

  PageHeader {
    id: head
    visible: root.paged
    width: parent.width
    app: root.app
    title: root.isNew ? "New contact" : "Contact"
    IconButton {
      visible: !root.isNew
      app: root.app
      glyph: root.app.glyphs.remove
      label: "Delete this contact"
      onClicked: root.app.askDelete(root.draftId)
    }
    IconButton {
      app: root.app
      glyph: root.app.glyphs.check
      color: root.app.ui.accent
      label: "Save"
      onClicked: root.save()
    }
  }

  Item {
    id: paneHead
    visible: !root.paged
    width: parent.width
    height: visible ? 64 : 0
    Text {
      x: 20
      anchors.verticalCenter: parent.verticalCenter
      text: root.isNew ? "New contact" : "Contact"
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      font.weight: Font.DemiBold
    }
    Row {
      anchors.right: parent.right
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      IconButton {
        visible: !root.isNew
        app: root.app
        glyph: root.app.glyphs.remove
        label: "Delete this contact"
        onClicked: root.app.askDelete(root.draftId)
      }
      IconButton {
        app: root.app
        glyph: root.app.glyphs.close
        label: "Close"
        onClicked: root.app.closeEditor()
      }
    }
  }

  // ------------------------------------------------------------ the form

  Flickable {
    id: flick
    anchors.top: root.paged ? head.bottom : paneHead.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: form.implicitHeight + 40 + root.app.bottomInset
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: form
      x: root.paged ? root.app.ui.gutter + 4 : 20
      y: 4
      width: Math.min(flick.width - x * 2, 560)
      spacing: 16

      Row {
        spacing: 16
        Avatar {
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          contact: ({ name: nameField.text, phone: phoneField.text, email: emailField.text, note: "" })
          size: 64
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: form.width - 80
          spacing: 2
          Text {
            width: parent.width
            text: nameField.text.trim() || phoneField.text.trim() || emailField.text.trim() || (root.isNew ? "Somebody new" : "Untitled")
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.lg + 3
            font.weight: Font.Bold
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: "Saved on this computer, nowhere else"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
        }
      }

      TextField {
        id: nameField
        width: parent.width
        app: root.app
        label: "Name"
        placeholder: "Name"
        onAccepted: root.save()
      }
      TextField {
        id: phoneField
        width: parent.width
        app: root.app
        label: "Phone"
        placeholder: "+44 7700 900000"
        inputHints: Qt.ImhDialableCharactersOnly
        onAccepted: root.save()
      }
      TextField {
        id: emailField
        width: parent.width
        app: root.app
        label: "Email"
        placeholder: "name@example.com"
        inputHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
        onAccepted: root.save()
      }
      Column {
        width: parent.width
        spacing: 6
        Text {
          text: "Note"
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.weight: Font.DemiBold
        }
        TextArea {
          id: noteArea
          width: parent.width
          implicitHeight: 110
          app: root.app
          placeholder: "Where you met, whose birthday, which door"
        }
      }

      Row {
        spacing: 10
        Button {
          app: root.app
          primary: true
          glyph: root.app.glyphs.check
          text: root.isNew ? "Add" : "Save"
          onClicked: root.save()
        }
        Button {
          visible: !root.paged
          app: root.app
          text: "Cancel"
          onClicked: root.app.closeEditor()
        }
      }
    }
  }
}
