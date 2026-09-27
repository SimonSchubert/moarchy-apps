pragma ComponentBehavior: Bound

import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Forecast.js" as Forecast
import "Store.js" as Places

// The places: a search for a town, where the computer is, and the towns
// somebody saved. A page of its own on a phone; the list beside the forecast
// on a desktop. Tapping a found town adds it and shows it -- that is the
// whole of "adding a place".
Item {
  id: root
  property var app

  readonly property bool searching: app.query.trim().length >= 2

  Connections {
    target: root.app
    function onSearchWanted() { if (root.visible) search.input.forceActiveFocus() }
    // Cleared from outside -- Escape, a place added -- and the field follows.
    function onQueryChanged() { if (search.text !== root.app.query) search.text = root.app.query }
  }
  Connections {
    target: search.input
    function onAccepted() { root.app.runSearch() }
  }
  Component.onCompleted: search.text = app.query

  SearchField {
    id: search
    app: root.app
    x: 10
    y: 10
    width: parent.width - 20
    placeholder: "Town or city"
    onTextChanged: if (text !== root.app.query) root.app.typed(text)
    onEscaped: root.app.resetFocus()
  }

  Flickable {
    anchors.top: search.bottom
    anchors.topMargin: 8
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: list.implicitHeight + 16
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: list
      x: 6
      width: parent.width - 12
      spacing: 2

      // ------------------------------------------------ what the search found
      Repeater {
        model: root.searching ? root.app.results : []
        delegate: ListRow {
          required property var modelData
          app: root.app
          width: list.width
          glyph: KG.plus
          title: modelData.name
          text: Forecast.where(modelData)
          onClicked: root.app.addPlace(modelData)
        }
      }
      EmptyState {
        visible: root.searching && !root.app.results.length
        anchors.horizontalCenter: parent.horizontalCenter
        width: list.width - 24
        app: root.app
        busy: root.app.finding
        glyph: KG.search
        title: root.app.finding ? "Looking…" : root.app.searched ? "Nothing found" : ""
        text: root.app.finding ? "Asking the geocoder for “" + root.app.query.trim() + "”."
          : root.app.searched ? "Nothing is called “" + root.app.query.trim() + "”." : ""
      }

      // ------------------------------------------------ the first run
      EmptyState {
        visible: !root.searching && !root.app.somewhere
        anchors.horizontalCenter: parent.horizontalCenter
        width: list.width - 24
        app: root.app
        glyph: G.places
        title: "Nowhere yet"
        text: "Type a town above — Vienna, Kyoto, Reykjavík — and tap it."
      }

      // ------------------------------------------------ where it is
      Text {
        visible: !root.searching && root.app.locate
        x: 10
        topPadding: 8
        bottomPadding: 4
        text: "Where you are"
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        font.weight: Font.DemiBold
      }
      Repeater {
        model: !root.searching && root.app.locate ? [{ here: true }] : []
        delegate: placeRow
      }

      // ------------------------------------------------ the saved ones
      Text {
        visible: !root.searching && root.app.places.length > 0
        x: 10
        topPadding: 12
        bottomPadding: 4
        text: "Saved"
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xs
        font.weight: Font.DemiBold
      }
      Repeater {
        model: root.searching ? [] : root.app.places
        delegate: placeRow
      }
    }
  }

  // One row of either list. A saved place, or { here: true } for the
  // computer's own, whose town may not be known yet.
  Component {
    id: placeRow
    ListRow {
      id: row
      required property var modelData
      readonly property bool isHere: modelData.here === true
      readonly property var shows: isHere ? root.app.here : modelData
      readonly property string key: isHere ? Places.HERE : modelData.id
      readonly property string cached: shows ? shows.id : ""
      app: root.app
      width: list.width
      glyph: isHere ? G.places : ""
      glyphColor: root.app.ui.accent
      selected: key === root.app.currentId && !!shows
      title: shows ? shows.name : (root.app.locating ? "Finding where you are…" : "Not found yet")
      text: {
        if (shows) return Forecast.where(shows)
        if (root.app.offline) return "This run is offline."
        return root.app.lost || "Asking GeoJS where this connection is."
      }
      onClicked: {
        if (shows) root.app.selectPlace(key)
        else root.app.findHere(true)
      }

      Sky {
        visible: root.app.glyphAt(row.cached).length > 0
        anchors.verticalCenter: parent.verticalCenter
        kind: root.app.glyphAt(row.cached) || "cloud"
        size: 24
        ink: root.app.ui.text
        accent: root.app.ui.rain
        spark: root.app.ui.sun
        behind: root.app.ui.surface
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: 48
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignRight
          text: root.app.tempAt(row.cached)
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.weight: Font.DemiBold
        }
        Text {
          width: parent.width
          visible: text.length > 0
          horizontalAlignment: Text.AlignRight
          text: root.app.clockAt(row.cached)
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
        }
      }
      // A typed town can be removed. The computer's own place cannot -- the
      // switch in Settings is how that goes -- so its button asks again.
      IconButton {
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        implicitWidth: 36
        implicitHeight: 36
        size: 17
        color: root.app.ui.muted
        glyph: row.isHere ? KG.refresh : KG.remove
        label: row.isHere ? "Look up where this connection is again" : "Remove " + (row.modelData.name || "")
        onClicked: {
          if (row.isHere) root.app.findHere(true)
          else root.app.removePlace(row.modelData.id)
        }
      }
    }
  }
}
