import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// Genres, countries or languages as a grid of cells: a badge, the name and
// how many stations. As many columns as fit, one on a phone.
Item {
  id: root
  property var app
  property string kind: "tags"
  property var items: []
  property bool loading: false
  property string error: ""
  property string emptyTitle: "Nothing here yet"
  signal activated(var facet)

  readonly property int pad: app.compact ? 6 : 16
  readonly property int columns: Math.max(1, Math.floor((width - pad * 2) / (app.compact ? 300 : 250)))
  property int cursor: -1

  clip: true

  function move(dx, dy) {
    var n = grid.count
    if (!n) return false
    if (cursor < 0) cursor = 0
    else cursor = Math.max(0, Math.min(n - 1, cursor + dx + dy * columns))
    grid.positionViewAtIndex(cursor, GridView.Contain)
    return true
  }
  function activateCurrent() {
    if (cursor < 0 || cursor >= items.length) return false
    root.activated(items[cursor])
    return true
  }
  function currentItem() { return null }
  function toTop() { grid.positionViewAtBeginning(); cursor = -1 }

  onItemsChanged: if (cursor >= items.length) cursor = -1

  Keyed { id: keyed; items: root.items }

  Placeholder {
    width: parent.width
    visible: keyed.count === 0
    app: root.app
    busy: root.loading && !root.error
    glyph: root.error ? G.alert : G.browse
    title: root.error ? root.error : root.loading ? "Loading…" : root.emptyTitle
    action: root.error ? "Try again" : ""
    onTriggered: root.app.refresh(true)
  }

  GridView {
    id: grid
    x: root.pad
    width: parent.width - root.pad * 2
    height: parent.height
    cellWidth: width / root.columns
    cellHeight: 60
    model: keyed
    reuseItems: true
    cacheBuffer: 600
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
      id: cell
      required property string key
      required property int index
      readonly property var modelData: keyed.at(key)
      readonly property bool current: index === root.cursor
      width: grid.cellWidth
      height: grid.cellHeight

      Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: root.app.ui.radius + 2
        color: cell.current ? root.app.ui.selected : mouse.pressed ? root.app.ui.pressed : mouse.containsMouse ? root.app.ui.hover : "transparent"
        border.width: cell.current ? 1 : 0
        border.color: root.app.ui.accent

        // A badge: a colour for a genre, the code for a country, the
        // language's first letters.
        Rectangle {
          id: badge
          x: 8
          anchors.verticalCenter: parent.verticalCenter
          width: 40
          height: 40
          radius: root.kind === "tags" ? 20 : root.app.ui.radius
          color: root.kind === "tags"
            ? Qt.hsla((cell.modelData.hue || 0) / 360, 0.6, root.app.ui.dark ? 0.42 : 0.55, 1)
            : root.app.ui.accentSoft
          Text {
            anchors.centerIn: parent
            text: root.kind === "tags" ? "#" : root.kind === "countries" ? (cell.modelData.code || "")
              : (cell.modelData.name || "").slice(0, 2)
            color: root.kind === "tags" ? "white" : root.app.ui.accent
            font.family: root.app.ui.font
            font.pixelSize: root.kind === "tags" ? 18 : 13
            font.weight: Font.Bold
          }
        }

        Column {
          anchors.left: badge.right
          anchors.leftMargin: 12
          anchors.right: chev.left
          anchors.rightMargin: 4
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1
          Text {
            width: parent.width
            text: root.kind === "tags" ? (cell.modelData.name || "").charAt(0).toUpperCase() + (cell.modelData.name || "").slice(1)
              : cell.modelData.name || ""
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: Api.group(cell.modelData.count || 0) + (cell.modelData.count === 1 ? " station" : " stations")
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
        }
        Icon {
          id: chev
          anchors.right: parent.right
          anchors.rightMargin: 4
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          text: G.chevronRight
          size: 18
          color: root.app.ui.muted
        }
        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: !root.app.compact
          cursorShape: Qt.PointingHandCursor
          onClicked: root.activated(cell.modelData)
        }
      }
    }

    footer: Item { width: grid.width; height: 24 }
  }
}
