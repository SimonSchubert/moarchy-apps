import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Address.js" as Address
import "Mailbox.js" as Mailbox
import "Glyphs.js" as G

// A message: who and when, the text, what came with it, and Reply, Reply all
// and Forward along the bottom. A page with a way back on a phone; the pane
// beside the folder on a desktop, with a way to close it.
//
// The text is StyledText, and every tag in it is the helper's own: links are
// "#n" into body.links, and nothing in a message can make this fetch a
// picture -- which is how a sender learns that, when and where it was read.
Item {
  id: root
  property var app
  property bool paged: false

  readonly property var row: app.shownRow
  readonly property var body: app.body
  readonly property bool starred: !!row && Mailbox.has(row, Mailbox.FLAGGED)

  // The top: a way back or out, and what can be done to this message.
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
      text: root.app.folderLabel
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.sm
      elide: Text.ElideRight
    }
    Row {
      id: actions
      anchors.right: parent.right
      anchors.rightMargin: root.paged ? 4 : 8
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      IconButton {
        app: root.app
        glyph: root.starred ? G.star : G.starOutline
        color: root.starred ? root.app.ui.star : root.app.ui.text
        label: root.starred ? "Remove the star" : "Star"
        onClicked: root.app.toggleStar(root.app.openRow)
      }
      IconButton {
        app: root.app
        glyph: G.trash
        label: "Delete"
        onClicked: root.app.remove(root.app.openRow)
      }
      IconButton {
        app: root.app
        glyph: G.more
        label: "More"
        onClicked: root.app.messageMenu()
      }
      IconButton {
        visible: !root.paged
        app: root.app
        glyph: KG.close
        label: "Close"
        onClicked: root.app.closeMessage()
      }
    }
  }

  Flickable {
    id: flick
    anchors.top: bar.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: replyBar.top
    anchors.bottomMargin: 8
    contentWidth: width
    contentHeight: col.implicitHeight + 16
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: col
      x: root.paged ? root.app.ui.gutter : 20
      width: Math.min(flick.width - x * 2, 820)
      spacing: 12

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.row ? ((root.body ? root.body.subject : root.row.subject) || "No subject") : ""
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.compact ? 20 : 22
        font.weight: Font.Bold
      }

      Card {
        app: root.app
        width: parent.width

        Row {
          width: parent.width
          spacing: 12
          Rectangle {
            width: 40
            height: 40
            radius: 20
            color: root.app.ui.surfaceHigh
            Text {
              anchors.centerIn: parent
              text: root.row ? Address.initial(root.row.from) : ""
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.lg
              font.weight: Font.DemiBold
            }
          }
          Column {
            width: parent.width - 52 - stamp.implicitWidth - 12
            anchors.verticalCenter: parent.verticalCenter
            Text {
              width: parent.width
              text: root.row ? (Address.label(root.row.from) || "Unknown sender") : ""
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
              font.weight: Font.DemiBold
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              visible: !!root.row && !!root.row.from && root.row.from.name.length > 0
              text: root.row && root.row.from ? root.row.from.email : ""
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.sm
              elide: Text.ElideRight
            }
          }
          Text {
            id: stamp
            text: root.row ? Mailbox.stamp(root.row.date || root.row.at, root.app.now) : ""
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
          }
        }

        Text {
          width: parent.width
          visible: text.length > 0
          text: {
            if (!root.body) return ""
            var to = root.body.to.map(Address.label).join(", ")
            var cc = root.body.cc.map(Address.label).join(", ")
            var out = to ? "To " + to : ""
            if (cc) out += (out ? "\nCc " : "Cc ") + cc
            return out
          }
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          wrapMode: Text.Wrap
          maximumLineCount: 4
          elide: Text.ElideRight
        }

        // The attachments are under the text, which on a long message is a
        // long way down. This says they are there, and goes to them.
        Row {
          visible: !!root.body && root.body.attachments.length > 0
          spacing: 4
          Icon { app: root.app; text: G.attachment; size: 14; color: root.app.ui.accent }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
              if (!root.body) return ""
              var files = root.body.attachments
              var total = 0
              for (var i = 0; i < files.length; i++) total += files[i].size
              return (files.length === 1 ? files[0].name : files.length + " attachments") + " · " + Mailbox.size(total)
            }
            color: root.app.ui.accent
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.sm
            elide: Text.ElideMiddle
            MouseArea {
              anchors.fill: parent
              anchors.margins: -8
              cursorShape: Qt.PointingHandCursor
              onClicked: flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, files.y))
            }
          }
        }
      }

      Card {
        app: root.app
        width: parent.width

        Text {
          width: parent.width
          visible: root.body !== null
          textFormat: Text.StyledText
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          text: root.app.bodyMarkup
          color: root.app.ui.text
          linkColor: root.app.ui.accent
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          lineHeight: 1.15
          onLinkActivated: function (link) { root.app.followLink(link) }
          HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        Text {
          width: parent.width
          visible: root.body !== null && !root.app.bodyMarkup.length
          text: "This message has no text in it."
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
        }
        Text {
          width: parent.width
          visible: root.body === null && root.app.bodyLoading
          wrapMode: Text.Wrap
          text: root.row && root.row.preview ? root.row.preview + "…" : "Downloading…"
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
        }
        Text {
          width: parent.width
          visible: root.body === null && !root.app.bodyLoading && root.app.bodyError.length > 0
          wrapMode: Text.Wrap
          text: root.app.bodyError
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
        }
        Button {
          visible: root.body === null && !root.app.bodyLoading && root.app.bodyError.length > 0 && !root.app.offline
          app: root.app
          text: "Try again"
          onClicked: root.app.fetchBody()
        }
        Text {
          width: parent.width
          visible: !!root.body && (root.body.pictures > 0 || root.body.truncated)
          wrapMode: Text.Wrap
          text: !root.body ? ""
            : root.body.truncated ? "The rest of this message is too long to show here."
            : root.body.pictures === 1 ? "1 picture is not shown."
            : root.body.pictures + " pictures are not shown."
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }

      Column {
        id: files
        width: parent.width
        visible: !!root.body && root.body.attachments.length > 0
        spacing: 2
        Text {
          text: "Attachments"
          bottomPadding: 4
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: Font.DemiBold
        }
        Repeater {
          model: root.body ? root.body.attachments : []
          delegate: ListRow {
            id: fileRow
            required property var modelData
            width: files.width
            app: root.app
            glyph: G.attachment
            title: modelData.name
            text: Mailbox.size(modelData.size)
            onClicked: root.app.saveAttachment(fileRow.modelData)
            Icon { app: root.app; text: G.download; size: 18; color: root.app.ui.text }
          }
        }
      }
    }
  }

  Row {
    id: replyBar
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 12 + (root.paged ? root.app.bottomInset : 0)
    x: root.paged ? root.app.ui.gutter : 20
    width: parent.width - x * 2
    height: root.body ? implicitHeight : 0
    visible: root.body !== null
    spacing: 8
    readonly property int count: root.app.canReplyAll ? 3 : 2
    readonly property real each: (width - spacing * (count - 1)) / count

    Button {
      width: root.paged ? replyBar.each : implicitWidth
      app: root.app
      primary: true
      glyph: G.reply
      text: "Reply"
      onClicked: root.app.reply(false)
    }
    Button {
      visible: root.app.canReplyAll
      width: root.paged ? replyBar.each : implicitWidth
      app: root.app
      glyph: G.replyAll
      text: "Reply all"
      onClicked: root.app.reply(true)
    }
    Button {
      width: root.paged ? replyBar.each : implicitWidth
      app: root.app
      glyph: G.forward
      text: "Forward"
      onClicked: root.app.forward()
    }
  }
}
