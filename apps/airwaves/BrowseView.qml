import QtQuick
import "Api.mjs" as Api
import "Glyphs.js" as G

// The directory by genre, by country and by language, biggest first, with a
// field that narrows the list as you type. A tap opens that part of it.
Item {
  id: root
  property var app

  readonly property string kind: ["tags", "countries", "languages"].indexOf(app.store.prefs.browse) >= 0 ? app.store.prefs.browse : "tags"
  readonly property string path: kind === "countries" ? Api.countriesPath() : kind === "languages" ? Api.languagesPath() : Api.tagsPath()
  property string query: ""

  readonly property var all: { app.api.revision; return app.api.peek(path) || [] }
  readonly property var items: {
    var q = query.trim().toLowerCase()
    if (!q) return all
    return all.filter(function (f) { return f.name.toLowerCase().indexOf(q) >= 0 || f.code.toLowerCase() === q })
  }
  readonly property bool loading: { app.api.revision; return app.api.busy(path) }
  readonly property string error: { app.api.revision; return app.api.error(path) }

  function refresh(force) { app.api.want(path, kind, force ? 0 : 86400000, true) }
  onPathChanged: { query = ""; refresh(false); grid.toTop() }

  function choose(k) { app.store.set("browse", k) }

  function open(f) {
    if (kind === "countries") app.openList({ facet: "country", value: f.code, label: f.name })
    else if (kind === "languages") app.openList({ facet: "language", value: f.code, label: f.name })
    else app.openList({ facet: "tag", value: f.code, label: f.name })
  }

  function focusField() { field.forceActiveFocus() }

  Column {
    id: bar
    width: parent.width
    topPadding: 4
    spacing: 12

    // Genres, countries or languages: a segmented control.
    Rectangle {
      x: grid.pad + 4
      width: seg.implicitWidth + 6
      height: root.app.ui.chip + 4
      radius: height / 2
      color: root.app.ui.surface
      border.width: 1
      border.color: root.app.ui.border
      Row {
        id: seg
        anchors.centerIn: parent
        Repeater {
          model: [{ k: "tags", l: "Genres", g: G.tag }, { k: "countries", l: "Countries", g: G.earth }, { k: "languages", l: "Languages", g: G.language }]
          delegate: Rectangle {
            id: segItem
            required property var modelData
            readonly property bool sel: root.kind === modelData.k
            width: segLabel.implicitWidth + (root.app.compact ? 24 : 36)
            height: root.app.ui.chip - 2
            radius: height / 2
            color: sel ? root.app.ui.accent : segMouse.containsMouse ? root.app.ui.hover : "transparent"
            Row {
              id: segLabel
              anchors.centerIn: parent
              spacing: 4
              Icon {
                anchors.verticalCenter: parent.verticalCenter
                app: root.app
                text: segItem.modelData.g
                size: 15
                width: 18
                color: segItem.sel ? root.app.onAccent : root.app.ui.text
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: segItem.modelData.l
                color: segItem.sel ? root.app.onAccent : root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
                font.weight: Font.DemiBold
              }
            }
            MouseArea {
              id: segMouse
              anchors.fill: parent
              hoverEnabled: !root.app.compact
              cursorShape: Qt.PointingHandCursor
              onClicked: root.choose(segItem.modelData.k)
            }
          }
        }
      }
    }

    Rectangle {
      x: grid.pad + 4
      width: Math.min(parent.width - x * 2, 520)
      height: 42
      radius: 21
      color: root.app.ui.surface
      border.width: 1
      border.color: field.activeFocus ? root.app.ui.accent : root.app.ui.border
      Icon {
        id: lens
        app: root.app
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        text: G.search
        size: 17
        color: root.app.ui.muted
      }
      TextInput {
        id: field
        anchors.left: lens.right
        anchors.leftMargin: 4
        anchors.right: clearBtn.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        verticalAlignment: TextInput.AlignVCenter
        text: root.query
        onTextEdited: root.query = text
        color: root.app.ui.text
        selectionColor: root.app.ui.accent
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
        clip: true
        inputMethodHints: Qt.ImhNoPredictiveText
        Keys.onEscapePressed: function (event) {
          if (root.query) { root.query = ""; event.accepted = true }
          else { root.app.resetFocus(); event.accepted = true }
        }
        Keys.onDownPressed: { root.app.resetFocus(); grid.move(0, 0) }
        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          visible: !field.text
          text: root.kind === "countries" ? "Find a country" : root.kind === "languages" ? "Find a language" : "Find a genre"
          color: root.app.ui.muted
          font: field.font
        }
      }
      IconButton {
        id: clearBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: root.query !== ""
        width: visible ? implicitWidth : 10
        app: root.app
        glyph: G.close
        label: "Clear"
        size: 15
        onClicked: { root.query = ""; field.forceActiveFocus() }
      }
    }
  }

  FacetGrid {
    id: grid
    anchors.top: bar.bottom
    anchors.topMargin: 12
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    app: root.app
    kind: root.kind
    items: root.items
    loading: root.loading
    error: root.all.length ? "" : root.error
    emptyTitle: root.query ? "Nothing matches “" + root.query.trim() + "”" : "Nothing here yet"
    onActivated: function (f) { root.open(f) }
  }

  property alias list: grid
}
