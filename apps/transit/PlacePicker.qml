import QtQuick
import "Api.mjs" as Api

// Choosing a place: a search field over everything, with home, work, your
// stops and recent places ready before a letter is typed. The geocoder is
// asked 300 ms after the last keystroke, not on every one.
Rectangle {
  id: root
  property var app
  property string which: ""

  readonly property bool stopsOnly: which === "board"
  property string text: ""
  property string asked: ""
  readonly property var near: app.store.homePlace || app.query.from || app.store.board
  readonly property string url: Api.geocodeUrl(asked, app.lang, near, stopsOnly)
  readonly property var results: { app.motis.revision; return url ? app.motis.peek(url) || [] : [] }
  readonly property bool loading: { app.motis.revision; return url !== "" && app.motis.busy(url) }
  readonly property string error: { app.motis.revision; return url ? app.motis.error(url) : "" }

  readonly property string title: which === "from" ? "From" : which === "to" ? "To"
    : which === "board" ? "Stop" : which === "home" ? "Home" : which === "work" ? "Work" : ""

  // Ready-made choices: home and work, favourite stops, and the places in
  // recent searches, without repeats.
  readonly property var quick: {
    var out = []
    var s = app.store
    function add(p, glyph, label) {
      if (!p) return
      if (root.stopsOnly && p.type !== "STOP") return
      for (var i = 0; i < out.length; i++) if (Api.samePlace(out[i].place, p)) return
      out.push({ place: p, glyph: glyph, label: label })
    }
    if (which !== "home") add(s.homePlace, Api.GLYPH.home, "Home")
    if (which !== "work") add(s.workPlace, Api.GLYPH.work, "Work")
    for (var i = 0; i < s.stops.length; i++) add(s.stops[i], Api.GLYPH.star, "")
    for (var j = 0; j < s.recents.length; j++) {
      add(s.recents[j].to, Api.GLYPH.history, "")
      add(s.recents[j].from, Api.GLYPH.history, "")
    }
    return out.slice(0, 12)
  }
  // Stops first, in the geocoder's order: hotels and car parks named after
  // a station outnumber the station itself.
  readonly property var ranked: {
    var rank = { STOP: 0, ADDRESS: 1, PLACE: 2 }
    return results.map(function (p, i) { return { p: p, i: i } })
      .sort(function (a, b) { return (rank[a.p.type] - rank[b.p.type]) || a.i - b.i })
      .map(function (x) { return x.p })
  }
  readonly property var rows: text.trim().length >= 2 ? ranked.map(function (p) { return { place: p, glyph: "", label: "" } }) : quick

  color: app.ui.bg
  // Nothing under it takes a tap.
  MouseArea { anchors.fill: parent }

  onVisibleChanged: {
    if (!visible) return
    text = ""
    asked = ""
    input.text = ""
    Qt.callLater(function () { input.forceActiveFocus() })
  }

  Timer {
    id: debounce
    interval: 300
    onTriggered: {
      root.asked = root.text.trim()
      // A day: stop names do not move.
      if (root.url) root.app.motis.want(root.url, "geocode", 86400000, true)
    }
  }

  Item {
    id: header
    width: parent.width
    height: 64

    IconButton {
      id: backBtn
      x: 4
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      glyph: Api.GLYPH.back
      label: "Back"
      onClicked: root.app.back()
    }

    Rectangle {
      anchors.left: backBtn.right
      anchors.leftMargin: 4
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      height: 46
      radius: 23
      color: root.app.ui.surface
      border.width: 1
      border.color: input.activeFocus ? root.app.ui.accent : root.app.ui.border

      Text {
        id: tag
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
        font.weight: Font.DemiBold
      }

      TextInput {
        id: input
        anchors.left: tag.right
        anchors.leftMargin: 10
        anchors.right: clearBtn.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        verticalAlignment: TextInput.AlignVCenter
        color: root.app.ui.text
        selectionColor: root.app.ui.accent
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
        clip: true
        inputMethodHints: Qt.ImhNoPredictiveText
        onTextEdited: { root.text = text; debounce.restart() }
        onAccepted: {
          if (root.rows.length && root.text.trim().length >= 2 && root.asked === root.text.trim()) root.app.picked(root.rows[0].place)
          else { debounce.stop(); debounce.triggered() }
        }
        Keys.onDownPressed: list.forceActiveFocus()

        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          visible: !input.text
          text: root.stopsOnly ? "Stop or station" : "Stop, address or place"
          color: root.app.ui.muted
          font: input.font
          elide: Text.ElideRight
        }
      }

      IconButton {
        id: clearBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text !== ""
        width: visible ? implicitWidth : 8
        app: root.app
        glyph: Api.GLYPH.close
        size: 16
        label: "Clear"
        onClicked: { input.text = ""; root.text = ""; root.asked = ""; input.forceActiveFocus() }
      }
    }
  }

  ListView {
    id: list
    anchors.top: header.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.rows
    keyNavigationEnabled: true
    Keys.onReturnPressed: if (currentIndex >= 0 && root.rows[currentIndex]) root.app.picked(root.rows[currentIndex].place)
    Keys.onUpPressed: { if (currentIndex <= 0) input.forceActiveFocus(); else decrementCurrentIndex() }

    header: Item {
      width: list.width
      height: visible ? 40 : 0
      visible: root.text.trim().length < 2 && root.quick.length > 0
      SectionTitle {
        x: 20
        width: parent.width - 40
        anchors.bottom: parent.bottom
        app: root.app
        text: "Your places"
      }
    }

    delegate: Rectangle {
      id: rowItem
      required property var modelData
      required property int index
      readonly property var p: modelData.place
      width: list.width
      height: 60
      color: rowMouse.pressed ? root.app.ui.pressed : (list.activeFocus && list.currentIndex === index) || rowMouse.containsMouse ? root.app.ui.hover : "transparent"

      // What kind of place: the leading mode's colour tile for a stop, a pin
      // otherwise, or the saved place's own mark.
      Rectangle {
        id: tile
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 36
        radius: 10
        readonly property string mode: rowItem.p.modes && rowItem.p.modes.length ? rowItem.p.modes[0] : ""
        color: rowItem.modelData.glyph ? root.app.ui.surfaceHigh
          : rowItem.p.type === "STOP" ? root.app.alpha(Qt.color(Api.modeColor(mode)), 0.16) : root.app.ui.surfaceHigh
        Icon {
          anchors.centerIn: parent
          app: root.app
          size: 18
          text: rowItem.modelData.glyph || (rowItem.p.type === "STOP" ? Api.modeGlyph(tile.mode || "BUS") : rowItem.p.type === "ADDRESS" ? Api.GLYPH.marker : Api.GLYPH.markerOutline)
          color: rowItem.modelData.glyph === Api.GLYPH.star ? root.app.ui.star
            : rowItem.modelData.glyph ? root.app.ui.text
            : rowItem.p.type === "STOP" ? Api.modeColor(tile.mode || "BUS") : root.app.ui.muted
        }
      }

      Column {
        anchors.left: tile.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
          width: parent.width
          text: rowItem.modelData.label ? rowItem.modelData.label : rowItem.p.name
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: rowItem.modelData.label ? rowItem.p.name : rowItem.p.area
          visible: text !== ""
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          elide: Text.ElideRight
        }
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: !root.app.compact
        cursorShape: Qt.PointingHandCursor
        onClicked: root.app.picked(rowItem.p)
      }
    }

    footer: Item {
      width: list.width
      height: 120
      Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: 8
        Spinner {
          anchors.horizontalCenter: parent.horizontalCenter
          app: root.app
          running: root.loading
        }
        Text {
          width: parent.width - 40
          anchors.horizontalCenter: parent.horizontalCenter
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          visible: !root.loading && root.text.trim().length >= 2 && root.asked !== "" && root.results.length === 0
          text: root.error || "Nothing by that name. Try the station's full name, or a street and town."
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
        Text {
          width: parent.width - 40
          anchors.horizontalCenter: parent.horizontalCenter
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          visible: root.text.trim().length < 2 && root.quick.length === 0
          text: "Search any station, stop, street or place, worldwide."
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }
    }
  }
}
