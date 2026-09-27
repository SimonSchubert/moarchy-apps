import QtQuick
import "Api.mjs" as Api

// Everything kept: home and work, your stops for the departure board, and
// your trips.
Item {
  id: root
  property var app
  property alias flick: flick

  function refresh(force) {}

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: body.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    Column {
      id: body
      x: (flick.width - width) / 2
      y: 4
      width: Math.min(flick.width - 28, 720)
      spacing: 12

      // -------------------------------------------------------- places
      Row {
        width: parent.width
        spacing: 10
        Repeater {
          model: [
            { key: "home", label: "Home", glyph: Api.GLYPH.home },
            { key: "work", label: "Work", glyph: Api.GLYPH.work }
          ]
          delegate: Card {
            id: placeCard
            required property var modelData
            readonly property var place: modelData.key === "home" ? root.app.store.homePlace : root.app.store.workPlace
            width: (body.width - 10) / 2
            app: root.app
            pressable: true
            onClicked: place ? root.app.plan(root.app.query.from && !Api.samePlace(root.app.query.from, place) ? root.app.query.from : null, place) : root.app.pick(modelData.key)
            Column {
              width: parent.width
              spacing: 8
              Item {
                width: parent.width
                height: 36
                Rectangle {
                  width: 36
                  height: 36
                  radius: 10
                  color: root.app.ui.accentSoft
                  Icon { anchors.centerIn: parent; app: root.app; text: placeCard.modelData.glyph; size: 18; color: root.app.ui.accent }
                }
                IconButton {
                  anchors.right: parent.right
                  anchors.rightMargin: -8
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !!placeCard.place
                  app: root.app
                  glyph: Api.GLYPH.settings
                  size: 16
                  color: root.app.ui.muted
                  label: "Change " + placeCard.modelData.label.toLowerCase()
                  onClicked: root.app.pick(placeCard.modelData.key)
                }
              }
              Text {
                text: placeCard.modelData.label
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.md
                font.weight: Font.DemiBold
              }
              Text {
                width: parent.width
                text: placeCard.place ? placeCard.place.name : "Set " + placeCard.modelData.label.toLowerCase()
                color: placeCard.place ? root.app.ui.muted : root.app.ui.accent
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.xs
                elide: Text.ElideRight
              }
            }
          }
        }
      }

      // -------------------------------------------------------- stops
      SectionTitle {
        width: parent.width
        app: root.app
        text: "Your stops"
        action: "Add"
        onTriggered: root.app.pick("board")
      }
      Text {
        visible: root.app.store.stops.length === 0
        width: parent.width
        wrapMode: Text.Wrap
        text: "Star a stop on its departure board to keep it here."
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
      Card {
        visible: root.app.store.stops.length > 0
        width: parent.width
        app: root.app
        pad: 0
        Column {
          width: parent.width
          Repeater {
            model: root.app.store.stops
            delegate: SavedRow {
              required property var modelData
              required property int index
              width: parent.width
              app: root.app
              glyph: modelData.modes && modelData.modes.length ? Api.modeGlyph(modelData.modes[0]) : Api.GLYPH.stop
              glyphColor: modelData.modes && modelData.modes.length ? Api.modeColor(modelData.modes[0]) : root.app.ui.muted
              title: modelData.name
              subtitle: modelData.area
              divider: index > 0
              onClicked: root.app.openBoard(modelData)
              onRemoved: root.app.store.toggleStop(modelData)
            }
          }
        }
      }

      // -------------------------------------------------------- trips
      SectionTitle {
        width: parent.width
        app: root.app
        text: "Your trips"
      }
      Text {
        visible: root.app.store.trips.length === 0
        width: parent.width
        wrapMode: Text.Wrap
        text: "Star a search to keep the trip here and see its next connection on the Journey tab."
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
      Card {
        visible: root.app.store.trips.length > 0
        width: parent.width
        app: root.app
        pad: 0
        Column {
          width: parent.width
          Repeater {
            model: root.app.store.trips
            delegate: SavedRow {
              required property var modelData
              required property int index
              width: parent.width
              app: root.app
              glyph: Api.GLYPH.route
              glyphColor: root.app.ui.accent
              title: modelData.to.name
              subtitle: "from " + modelData.from.name
              divider: index > 0
              canMoveUp: index > 0
              onClicked: root.app.plan(modelData.from, modelData.to)
              onRemoved: root.app.store.toggleTrip(modelData.from, modelData.to)
              onMovedUp: root.app.store.moveTrip(index, -1)
            }
          }
        }
      }
    }
  }
}
