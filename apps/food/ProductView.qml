import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Facts.js" as F

// One product: the front of the packet when there is a picture of it, the
// name, three grades, the table per 100 g, the allergens, the ingredients.
// The Nutri-Score is the size of a thumb because it is the one fact a person
// in a supermarket aisle came for; the table is what they stay for.
//
// `paged` is a page of its own on a phone, with a back arrow; otherwise it is
// the pane beside the history, with a close button.
Item {
  id: root
  property var app
  property var product: null
  property bool paged: false
  // A local file of the front-of-pack thumbnail, or "".
  property string image: ""
  signal removed()
  signal closed()

  PageHeader {
    id: head
    visible: root.paged
    width: parent.width
    app: root.app
    title: root.product ? root.product.name : ""
    subtitle: root.product ? (F.subtitle(root.product) || root.product.code) : ""
    IconButton { app: root.app; glyph: KG.remove; label: "Remove from history"; onClicked: root.removed() }
  }

  Row {
    id: paneHead
    visible: !root.paged
    anchors.right: parent.right
    anchors.rightMargin: 8
    y: 8
    spacing: 2
    z: 2
    IconButton { app: root.app; glyph: KG.remove; label: "Remove from history"; onClicked: root.removed() }
    IconButton { app: root.app; glyph: KG.close; label: "Close"; onClicked: root.closed() }
  }

  Flickable {
    id: flick
    anchors.top: root.paged ? head.bottom : parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: body.implicitHeight + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      x: root.app.ui.gutter
      y: root.paged ? 4 : 18
      width: flick.width - x * 2
      spacing: 14

      Image {
        visible: root.image !== "" && status === Image.Ready
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, 220)
        height: visible ? 140 : 0
        source: root.image ? "file://" + root.image : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
      }

      Column {
        width: parent.width - (root.paged ? 0 : 80)
        spacing: 3
        Text {
          visible: !root.paged
          width: parent.width
          wrapMode: Text.Wrap
          text: root.product ? root.product.name : ""
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.lg + 5
          font.weight: Font.Bold
        }
        Text {
          visible: !root.paged
          width: parent.width
          wrapMode: Text.Wrap
          text: root.product ? (F.subtitle(root.product) || root.product.code) : ""
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 22
        GradeBadge {
          app: root.app
          grade: root.product ? root.product.nutriscore : ""
          caption: "Nutri-Score"
        }
        // NOVA is a number, not a letter of the Nutri-Score alphabet, so the
        // caption carries the words and the badge carries 1-4.
        GradeBadge {
          app: root.app
          fallback: root.product && root.product.nova ? String(root.product.nova) : F.DASH
          caption: root.product && root.product.nova ? F.novaLabel(root.product) : "NOVA"
        }
        GradeBadge {
          app: root.app
          grade: root.product ? root.product.ecoscore : ""
          caption: "Eco-Score"
        }
      }

      Card {
        visible: root.product !== null && root.product.nutrients.length > 0
        app: root.app
        width: parent.width
        title: "Per 100 g"
        Repeater {
          model: root.product ? root.product.nutrients : []
          delegate: Item {
            required property var modelData
            width: parent.width
            height: 26
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: F.drawn(modelData)
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
              font.weight: Font.DemiBold
              font.features: ({ "tnum": 1 })
            }
          }
        }
      }

      Text {
        visible: root.product !== null && root.product.allergens.length > 0
        width: parent.width
        wrapMode: Text.Wrap
        text: root.product ? "Allergens: " + root.product.allergens.join(" · ") : ""
        color: root.app.ui.warn
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
        font.weight: Font.DemiBold
      }

      Text {
        visible: root.product !== null && root.product.ingredients !== ""
        width: parent.width
        wrapMode: Text.Wrap
        lineHeight: 1.15
        text: root.product ? root.product.ingredients : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.product ? root.product.code + (root.product.additives !== null ? " · " + root.product.additives + " additive" + (root.product.additives === 1 ? "" : "s") : "") : ""
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
      }
    }
  }
}
