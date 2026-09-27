import QtQuick
import "kit"
import "Address.js" as Address
import "Compose.js" as Compose
import "Mailbox.js" as Mailbox
import "Glyphs.js" as G

// A folder: its messages, newest first, unread in bold. In the Inbox, what
// did not send and the drafts come first -- the two things waiting on the
// person holding the phone rather than on a server.
Item {
  id: root
  property var app

  readonly property int gutter: app.wide ? 12 : app.ui.gutter

  SearchField {
    id: search
    visible: root.app.searching
    x: root.gutter
    y: 4
    width: parent.width - root.gutter * 2
    height: visible ? implicitHeight : 0
    app: root.app
    placeholder: "Search this folder"
    text: root.app.query
    onTextChanged: root.app.query = text
    onEscaped: root.app.endSearch()
    Component.onCompleted: if (root.app.searching) input.forceActiveFocus()
    Connections {
      target: root.app
      function onSearchingChanged() { if (root.app.searching) search.input.forceActiveFocus() }
    }
  }

  EmptyState {
    anchors.horizontalCenter: parent.horizontalCenter
    y: search.y + search.height + 48
    visible: root.app.boxLoaded && root.app.rows.length === 0 && root.app.extras.length === 0
    app: root.app
    busy: !root.app.searching && (root.app.syncing || root.app.box.at === 0) && !root.app.syncError
    glyph: root.app.syncError ? G.offline : G.read
    title: root.app.searching ? "Nothing matches"
      : root.app.syncError ? "Could not check for mail"
      : root.app.syncing || root.app.box.at === 0 ? "Checking for mail"
      : "Nothing in " + root.app.folderLabel
    text: root.app.searching ? "Only the messages already on this computer are searched."
      : root.app.syncError || (root.app.syncing || root.app.box.at === 0 ? "" : "New messages show up here.")
  }

  ListView {
    id: list
    anchors.top: search.bottom
    anchors.topMargin: search.visible ? 8 : 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.gutter
    anchors.rightMargin: root.gutter
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.app.rows
    spacing: 2
    // The pencil sits over the last rows on a phone; this keeps one clear.
    bottomMargin: root.app.wide ? 12 : 88
    currentIndex: root.app.cursor
    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

    header: Column {
      width: ListView.view ? ListView.view.width : 0
      bottomPadding: root.app.extras.length ? 6 : 0

      Repeater {
        model: root.app.extras
        delegate: ListRow {
          id: extraRow
          required property var modelData
          readonly property bool failed: modelData.kind === "outbox" && modelData.item.status === "failed"
          width: parent ? parent.width : 0
          app: root.app
          color: failed ? root.app.ui.alpha(root.app.ui.unsent, 0.14) : "transparent"
          glyph: modelData.kind === "draft" ? G.draft : G.sending
          glyphColor: failed ? root.app.ui.unsent : root.app.ui.muted
          title: Compose.summary(modelData.kind === "outbox" ? modelData.item.draft : modelData.item)
          text: modelData.kind === "draft" ? "Draft"
            : failed ? "Not sent · " + modelData.item.error
            : "Sending…"
          onClicked: root.app.openExtra(extraRow.modelData)
          onPressAndHold: root.app.extraMenu(extraRow.modelData)
        }
      }
    }

    delegate: MailRow {
      required property var modelData
      required property int index
      width: ListView.view ? ListView.view.width : 0
      app: root.app
      row: modelData
      selected: root.app.wide && (root.app.openRow ? root.app.openRow.uid === modelData.uid : root.app.cursor === index)
      onOpened: root.app.openMessage(modelData)
      onHeld: root.app.rowMenu(modelData)
    }

    footer: Item {
      width: ListView.view ? ListView.view.width : 0
      height: root.app.box.more && !root.app.searching ? 60 : 0
      visible: height > 0
      Button {
        anchors.centerIn: parent
        app: root.app
        text: root.app.loadingOlder ? "Fetching older messages…" : "Older messages"
        enabled: !root.app.loadingOlder
        onClicked: root.app.refresh(true)
      }
    }
  }
}
