import QtQuick
import "Api.mjs" as Api
import "Cols.js" as Cols

// One coin in a list: the markets table, the watchlist, search, trending.
//
// Only the layout in use is built. The figures to the right of the name are
// one of two components behind a Loader, and optional pieces (the star, the
// rank, the sparkline) are Loaders too: a phone row makes no desktop columns
// and no sparkline it would only hide.
Item {
  id: root
  property var app
  property var coin: ({})
  property bool selected: false
  property bool showStar: true
  property string subtitle: ""
  signal activated()

  readonly property var cols: Cols.layout(width)

  // Rows built from search or trending carry only some figures until their
  // prices arrive; a missing one is a dash, never a zero.
  function n(v) { return v === undefined || v === null ? NaN : v }
  readonly property string cur: app.currency
  readonly property bool starred: { app.store.prefs; return app.store.starred(coin.id) }

  readonly property real figuresWidth: cols.compact
    ? cols.price + (cols.spark ? cols.sparkW + 12 : 0)
    : cols.price + cols.pct * (1 + (cols.h1 ? 1 : 0) + (cols.d7 ? 1 : 0))
      + cols.money * ((cols.vol ? 1 : 0) + (cols.mcap ? 1 : 0)) + (cols.spark ? cols.sparkW + 12 : 0)

  implicitHeight: cols.compact ? 60 : 52
  Accessible.role: Accessible.ListItem
  Accessible.name: (coin.name || "") + " " + Api.price(n(coin.price), cur)

  Rectangle {
    anchors.fill: parent
    color: root.selected ? root.app.ui.selected : rowMouse.pressed ? root.app.ui.pressed
      : rowMouse.containsMouse ? root.app.ui.hover : "transparent"
  }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  Row {
    id: line
    anchors.fill: parent
    anchors.leftMargin: root.showStar ? 0 : 12
    anchors.rightMargin: 12

    Loader {
      active: root.showStar
      width: active ? root.app.ui.target : 0
      anchors.verticalCenter: parent.verticalCenter
      sourceComponent: IconButton {
        app: root.app
        glyph: root.starred ? "󰓎" : "󰓒"
        label: root.starred ? "Remove from watchlist" : "Add to watchlist"
        color: root.starred ? root.app.ui.star : root.app.ui.muted
        size: 18
        onClicked: root.app.store.toggleStar(root.coin.id)
      }
    }

    Loader {
      active: root.cols.rank
      width: active ? 40 : 0
      anchors.verticalCenter: parent.verticalCenter
      sourceComponent: Text {
        text: isNaN(root.n(root.coin.rank)) ? "" : root.coin.rank
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
        font.features: ({ "tnum": 1 })
      }
    }

    // Name column: whatever is left once the figures have their room.
    Item {
      width: line.width - (root.showStar ? root.app.ui.target : 0) - (root.cols.rank ? 40 : 0) - root.figuresWidth
      height: parent.height

      CoinLogo {
        id: logo
        app: root.app
        anchors.verticalCenter: parent.verticalCenter
        size: root.cols.compact ? 30 : 26
        source: root.coin.image || ""
        symbol: root.coin.symbol || ""
      }

      Column {
        anchors.left: logo.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Row {
          width: parent.width
          spacing: 6
          Text {
            id: primary
            width: Math.min(implicitWidth, parent.width - (secondary.visible ? secondary.implicitWidth + 6 : 0))
            text: root.cols.compact ? (root.coin.symbol || "") : (root.coin.name || "")
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          Text {
            id: secondary
            anchors.baseline: primary.baseline
            visible: !root.cols.compact || !isNaN(root.n(root.coin.rank))
            text: root.cols.compact ? "#" + root.coin.rank : (root.coin.symbol || "")
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.xs
          }
        }
        Text {
          visible: root.cols.compact
          width: parent.width
          text: root.subtitle || root.coin.name || ""
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.xs
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }
    }

    Loader {
      width: root.figuresWidth
      height: parent.height
      sourceComponent: root.cols.compact ? compactFigures : wideFigures
    }
  }

  // Phone: an optional sparkline, then price over the 24h change.
  Component {
    id: compactFigures
    Row {
      Loader {
        active: root.cols.spark
        width: active ? root.cols.sparkW + 12 : 0
        height: 26
        anchors.verticalCenter: parent.verticalCenter
        // Wrapped: a Loader with a size stretches its item to it.
        sourceComponent: Item {
          Sparkline {
            app: root.app
            width: root.cols.sparkW
            height: 26
            points: root.coin.spark || []
          }
        }
      }
      Column {
        width: root.cols.price
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignRight
          text: Api.price(root.n(root.coin.price), root.cur)
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.md
          font.weight: Font.Medium
          font.features: ({ "tnum": 1 })
          fontSizeMode: Text.HorizontalFit
          minimumPixelSize: root.app.ui.fs.xs
        }
        Change {
          anchors.right: parent.right
          app: root.app
          value: root.n(root.coin.ch24)
          font.pixelSize: root.app.ui.fs.xs
        }
      }
    }
  }

  // Desktop: one figure per column, as many columns as the width allows.
  Component {
    id: wideFigures
    Row {
      Text {
        width: root.cols.price
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: Api.price(root.n(root.coin.price), root.cur)
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.md
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: root.app.ui.fs.xs
      }
      Change {
        visible: root.cols.h1
        width: root.cols.pct
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        app: root.app
        value: root.n(root.coin.ch1h)
      }
      Change {
        width: root.cols.pct
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        app: root.app
        value: root.n(root.coin.ch24)
      }
      Change {
        visible: root.cols.d7
        width: root.cols.pct
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        app: root.app
        value: root.n(root.coin.ch7d)
      }
      Text {
        visible: root.cols.vol
        width: root.cols.money
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: Api.money(root.n(root.coin.vol), root.cur)
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
        font.features: ({ "tnum": 1 })
      }
      Text {
        visible: root.cols.mcap
        width: root.cols.money
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: Api.money(root.n(root.coin.mcap), root.cur)
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
        font.features: ({ "tnum": 1 })
      }
      Loader {
        active: root.cols.spark
        width: active ? root.cols.sparkW + 12 : 0
        height: 30
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: Item {
          Sparkline {
            x: 12
            app: root.app
            width: root.cols.sparkW
            height: 30
            points: root.coin.spark || []
          }
        }
      }
    }
  }

  Rectangle {
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: 12
    anchors.rightMargin: 12
    height: 1
    color: root.app.ui.divider
  }
}
