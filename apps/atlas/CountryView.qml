import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Countries.js" as C

// One country, out of the list already in memory -- no request of its own:
// the flag large, the name in its own language, three figures with their
// place in the world, the facts, what REST Countries says about it, and the
// neighbours, each one a way to the next page.
//
// `paged` is a page of its own on a phone, with a back arrow; otherwise it is
// the pane beside the grid on a desktop, with a close button.
Item {
  id: root
  property var app
  property var country: null
  property var index: null
  property int total: 0
  property bool paged: false
  signal opened(string code)
  signal closed()

  readonly property var facts: C.facts(country)
  readonly property var tags: C.tags(country)
  readonly property var near: index ? C.neighbours(country, index) : []
  // The flag's own strongest colour, as a wash behind it: the page takes a
  // little of the country's colour without a colour of its own in the theme.
  readonly property color wash: country && country.tint
    ? Qt.tint(app.ui.surface, app.ui.alpha(country.tint, app.ui.dark ? 0.16 : 0.12)) : app.ui.surface

  function rank(map) {
    var r = country && map ? map[country.code] : 0
    return r ? "#" + r + " of " + total : ""
  }

  function toTop() { flick.contentY = 0 }
  onCountryChanged: toTop()

  PageHeader {
    id: head
    visible: root.paged
    width: parent.width
    height: visible ? implicitHeight : 0
    app: root.app
    title: root.country ? root.country.name : ""
    subtitle: root.country ? root.country.region : ""
  }

  IconButton {
    visible: !root.paged
    anchors.right: parent.right
    anchors.rightMargin: 10
    y: 10
    z: 2
    app: root.app
    glyph: KG.close
    label: "Close"
    onClicked: root.closed()
  }

  Flickable {
    id: flick
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: body.implicitHeight + 36
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      readonly property int side: root.app.compact ? 16 : 24
      x: side
      y: root.paged ? 12 : 18
      width: Math.min(flick.width - side * 2, 720)
      spacing: 18

      // The flag, on a band of its own colour.
      Rectangle {
        width: parent.width
        height: flag.height + (root.app.compact ? 36 : 48)
        radius: root.app.ui.radius
        color: root.wash
        border.width: 1
        border.color: root.app.ui.line
        Flag {
          id: flag
          anchors.centerIn: parent
          width: Math.min(parent.width - 40, root.app.compact ? 260 : 300)
          height: Math.round(width * 0.62)
          decodeWidth: 320
          app: root.app
          code: root.country ? root.country.code : ""
        }
      }

      Column {
        width: parent.width
        spacing: 4
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: root.country ? root.country.name : ""
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xl
          font.weight: Font.Bold
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          visible: text !== ""
          text: root.country && root.country.official !== root.country.name ? root.country.official : ""
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          visible: text !== ""
          text: root.country ? root.country["native"].slice(0, 3).join("  ·  ") : ""
          color: root.app.ui.accent
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
        }
      }

      Flow {
        width: parent.width
        spacing: 6
        visible: root.tags.length > 0
        Repeater {
          model: root.tags
          delegate: Badge {
            required property string modelData
            app: root.app
            text: modelData
          }
        }
      }

      // Three figures, and where each puts it among everybody.
      Row {
        id: tiles
        width: parent.width
        spacing: 8
        readonly property int tileWidth: Math.floor((width - spacing * 2) / 3)
        Repeater {
          model: root.country ? [
            { glyph: G.people, label: "People", value: C.compact(root.country.population), note: root.rank(root.index ? root.index.popRank : null) },
            { glyph: G.area, label: "Area km²", value: C.compact(root.country.area), note: root.rank(root.index ? root.index.areaRank : null) },
            { glyph: G.density, label: "Density", value: root.country.population && root.country.area ? C.compact(Math.round(root.country.population / root.country.area)) : C.DASH, note: root.country.population && root.country.area ? "per km²" : "" }
          ] : []
          delegate: Rectangle {
            required property var modelData
            width: tiles.tileWidth
            height: tileBody.implicitHeight + 24
            radius: root.app.ui.radius
            color: root.app.ui.surface
            border.width: 1
            border.color: root.app.ui.line
            Column {
              id: tileBody
              x: 12
              y: 12
              width: parent.width - 24
              spacing: 3
              Row {
                spacing: 4
                Icon {
                  anchors.verticalCenter: parent.verticalCenter
                  app: root.app
                  text: modelData.glyph
                  size: 13
                  width: 16
                  color: root.app.ui.muted
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: root.app.ui.muted
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.xs
                  font.capitalization: Font.AllUppercase
                  font.letterSpacing: root.app.ui.tracking
                }
              }
              Text {
                width: parent.width
                text: modelData.value
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.lg + (root.app.compact ? 1 : 5)
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: modelData.note || " "
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xs
                font.features: ({ "tnum": 1 })
                elide: Text.ElideRight
              }
            }
          }
        }
      }

      Card {
        app: root.app
        width: parent.width
        visible: root.facts.length > 0
        Grid {
          id: factGrid
          width: parent.width
          columns: width >= 480 ? 2 : 1
          columnSpacing: 20
          rowSpacing: 12
          Repeater {
            model: root.facts
            delegate: Column {
              required property var modelData
              width: (factGrid.width - factGrid.columnSpacing * (factGrid.columns - 1)) / factGrid.columns
              spacing: 2
              Text {
                text: modelData.label
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xs
                font.capitalization: Font.AllUppercase
                font.letterSpacing: root.app.ui.tracking
              }
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: modelData.value
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.md
                font.weight: Font.Bold
              }
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: 6
        visible: !!(root.country && root.country.about)
        SectionTitle { app: root.app; text: "About" }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          lineHeight: 1.25
          text: root.country ? root.country.about : ""
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
        }
      }

      Column {
        width: parent.width
        spacing: 6
        visible: !!(root.country && root.country.flagAbout)
        SectionTitle { app: root.app; text: "The flag" }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          lineHeight: 1.25
          text: root.country ? root.country.flagAbout : ""
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
        }
      }

      Column {
        width: parent.width
        spacing: 8
        visible: root.country !== null
        SectionTitle {
          app: root.app
          text: "Neighbours"
          note: root.country && root.country.borders.length ? String(root.country.borders.length) : ""
        }
        Text {
          visible: root.country !== null && root.country.borders.length === 0
          width: parent.width
          wrapMode: Text.Wrap
          text: "No land borders."
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: root.near
            delegate: Rectangle {
              id: chip
              required property var modelData
              width: chipRow.implicitWidth + 20
              height: root.app.ui.chip + 2
              radius: root.app.ui.radius
              color: chipMouse.pressed ? root.app.ui.pressed : chipMouse.containsMouse ? root.app.ui.hover : "transparent"
              border.width: 1
              border.color: root.app.ui.line
              Accessible.role: Accessible.Button
              Accessible.name: modelData.name
              Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 8
                Flag {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 24
                  height: 16
                  app: root.app
                  code: chip.modelData.code
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: chip.modelData.name
                  color: root.app.ui.text
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.sm
                }
              }
              MouseArea {
                id: chipMouse
                anchors.fill: parent
                hoverEnabled: !root.app.compact
                cursorShape: Qt.PointingHandCursor
                onClicked: root.opened(chip.modelData.code)
              }
            }
          }
        }
      }
    }
  }
}
