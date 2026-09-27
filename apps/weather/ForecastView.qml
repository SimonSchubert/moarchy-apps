pragma ComponentBehavior: Bound

import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Forecast.js" as Forecast

// The forecast for the place on screen: now, the next twenty-four hours, the
// wind and the ends of the day, and the week. One column on a phone, in the
// order the question is asked; two on a wide window, with the week beside the
// rest rather than a scroll below it.
Flickable {
  id: root
  property var app

  readonly property bool twoColumns: width >= 760
  readonly property real gutter: app.ui.gutter
  readonly property real columnWidth: twoColumns ? (width - gutter * 3) / 2 : width - gutter * 2

  contentWidth: width
  contentHeight: Math.max(left.y + left.height, right.y + right.height) + gutter
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  // Nothing known yet: the one sentence that says which of the reasons it is.
  EmptyState {
    visible: !root.app.reading
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.max(40, (root.height - implicitHeight) / 2 - 40)
    app: root.app
    busy: root.app.busy
    glyph: root.app.place ? KG.refresh : G.places
    title: {
      if (root.app.place) return "No forecast yet"
      if (root.app.locate && !root.app.lost && !root.app.offline) return "Finding where you are"
      return "Nowhere yet"
    }
    text: {
      var a = root.app
      if (!a.place) {
        if (a.offline) return "This run is offline."
        if (!a.locate) return "Name a town in Places and it opens here."
        if (a.lost) return a.lost + " Name a town in Places instead."
        return "Asking GeoJS where this connection is."
      }
      if (a.trouble) return a.trouble
      if (a.offline) return "This run is offline."
      return "Asking Open-Meteo…"
    }
    actionText: !root.app.place && root.app.compact ? "Places" : ""
    onAction: root.app.showPlaces()
  }

  Column {
    id: left
    visible: !!root.app.reading
    x: root.gutter
    y: root.app.compact ? 0 : 4
    width: root.columnWidth
    spacing: root.gutter

    // ---------------------------------------------------------- now
    Item {
      width: parent.width
      height: root.app.compact ? 200 : 220

      Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: 4

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 8
          Sky {
            anchors.verticalCenter: parent.verticalCenter
            kind: root.app.reading ? Forecast.glyph(root.app.reading.code, root.app.reading.day) : "cloud"
            size: root.app.compact ? 84 : 96
            ink: root.app.ui.text
            accent: root.app.ui.rain
            spark: root.app.ui.sun
            behind: root.app.ui.bg
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.app.reading ? Forecast.temperature(root.app.reading.temp, root.app.units) : ""
            // The theme's ink, not the temperature's colour: sixty pixels of
            // pale yellow on a light theme is the one place the hue would
            // cost a reading. The colour is in the strip and the bars.
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.compact ? 60 : 68
            font.weight: Font.Light
          }
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.app.reading ? Forecast.describe(root.app.reading.code) : ""
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.lg
          font.weight: Font.DemiBold
        }
        Text {
          width: parent.width
          visible: text.length > 0
          horizontalAlignment: Text.AlignHCenter
          text: Forecast.heroNote(root.app.reading, root.app.todayRow, root.app.units)
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }
    }

    // ---------------------------------------------------------- the hours
    Rectangle {
      width: parent.width
      height: 118
      visible: root.app.hours.length > 0
      radius: root.app.ui.radius + 4
      color: root.app.ui.surface
      border.width: 1
      border.color: root.app.ui.divider

      Flickable {
        id: strip
        anchors.fill: parent
        anchors.margins: 8
        clip: true
        contentWidth: hourRow.width
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        Row {
          id: hourRow
          height: strip.height
          Repeater {
            model: root.app.hours
            delegate: Item {
              id: hour
              required property var modelData
              readonly property bool isNow: Forecast.isNow(modelData.time, root.app.nowSec)
              width: 54
              height: hourRow.height

              // The hour it is now is marked by its label's colour as well
              // as the pill: one man in twelve cannot tell an accent from
              // the ink beside it.
              Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                radius: root.app.ui.radius
                visible: hour.isNow
                color: root.app.ui.surfaceHigh
              }
              Column {
                anchors.centerIn: parent
                spacing: 3
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Forecast.hourLabel(hour.modelData.time, root.app.zoneOffset, root.app.nowSec)
                  color: hour.isNow ? root.app.ui.text : root.app.ui.muted
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.xs
                  font.weight: hour.isNow ? Font.DemiBold : Font.Normal
                }
                Sky {
                  anchors.horizontalCenter: parent.horizontalCenter
                  kind: Forecast.glyph(hour.modelData.code, hour.modelData.day)
                  size: 26
                  ink: root.app.ui.text
                  accent: root.app.ui.rain
                  spark: root.app.ui.sun
                  behind: hour.isNow ? root.app.ui.surfaceHigh : root.app.ui.surface
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Forecast.temperature(hour.modelData.temp, root.app.units)
                  color: root.app.tempColour(hour.modelData.temp)
                  font.family: root.app.ui.font
                  font.pixelSize: root.app.ui.fs.md
                  font.weight: Font.DemiBold
                }
                // The chance of rain, only when there is one worth printing.
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  height: 12
                  text: hour.modelData.pop !== null && hour.modelData.pop >= 10 ? Forecast.percent(hour.modelData.pop) : ""
                  color: root.app.ui.rain
                  font.family: root.app.ui.font
                  font.pixelSize: 10
                }
              }
            }
          }
        }
      }
    }

    // ---------------------------------------------------------- the day
    Grid {
      width: parent.width
      visible: root.app.tiles.length > 0
      columns: 2
      columnSpacing: 10
      rowSpacing: 10
      Repeater {
        model: root.app.tiles
        delegate: Rectangle {
          id: tile
          required property var modelData
          width: (left.width - 10) / 2
          height: 72
          radius: root.app.ui.radius + 2
          color: root.app.ui.surface
          border.width: 1
          border.color: root.app.ui.divider
          Column {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 28
            spacing: 2
            Text {
              text: tile.modelData.label
              color: root.app.ui.muted
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.xs
            }
            Row {
              spacing: 6
              Text {
                id: tileValue
                text: tile.modelData.value
                color: root.app.ui.text
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.lg
                font.weight: Font.DemiBold
              }
              Text {
                anchors.baseline: tileValue.baseline
                visible: tile.modelData.note !== ""
                text: tile.modelData.note
                color: root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
              }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------- the week
  Column {
    id: right
    visible: root.app.week.length > 0 && !!root.app.reading
    x: root.twoColumns ? left.x + left.width + root.gutter : root.gutter
    y: root.twoColumns ? left.y + (root.app.compact ? 0 : 20) : left.y + left.height + root.gutter
    width: root.columnWidth

    Card {
      app: root.app
      width: parent.width
      title: "The week"
      Repeater {
        model: root.app.week
        delegate: Item {
          id: day
          required property var modelData
          readonly property var fraction: Forecast.bar(modelData, root.app.range)
          width: parent.width
          height: 44

          Text {
            id: dayName
            anchors.verticalCenter: parent.verticalCenter
            width: 52
            text: Forecast.dayLabel(day.modelData.time, root.app.zoneOffset, root.app.nowSec)
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            elide: Text.ElideRight
          }
          Sky {
            id: daySky
            anchors.left: dayName.right
            anchors.verticalCenter: parent.verticalCenter
            kind: Forecast.glyph(day.modelData.code, true)
            size: 26
            ink: root.app.ui.text
            accent: root.app.ui.rain
            spark: root.app.ui.sun
            behind: root.app.ui.surface
          }
          Text {
            id: pop
            anchors.left: daySky.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            text: day.modelData.pop !== null && day.modelData.pop >= 10 ? Forecast.percent(day.modelData.pop) : ""
            color: root.app.ui.rain
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
          Text {
            id: low
            anchors.left: pop.right
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            horizontalAlignment: Text.AlignRight
            text: Forecast.temperature(day.modelData.low, root.app.units)
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
          }
          // The week on one scale: a bar further right is a warmer day than
          // the row above it. Decoration -- both ends carry their number.
          Item {
            id: track
            anchors.left: low.right
            anchors.leftMargin: 10
            anchors.right: high.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            Rectangle {
              anchors.fill: parent
              radius: 3
              color: root.app.ui.well
            }
            Rectangle {
              x: day.fraction.from * track.width
              width: Math.max(6, (day.fraction.to - day.fraction.from) * track.width)
              height: parent.height
              radius: 3
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.app.tempColour(day.modelData.low) }
                GradientStop { position: 1.0; color: root.app.tempColour(day.modelData.high) }
              }
            }
          }
          Text {
            id: high
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            horizontalAlignment: Text.AlignRight
            text: Forecast.temperature(day.modelData.high, root.app.units)
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: Font.DemiBold
          }
        }
      }
    }
  }
}
