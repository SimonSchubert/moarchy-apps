import QtQuick
import "Api.mjs" as Api

// A buy or a sell, for the portfolio. Opens over whatever is on screen; on a
// phone it rises from the bottom, on a desktop it floats in the middle.
Item {
  id: root
  property var app
  property var coin: null
  property string side: "buy"
  signal done()

  readonly property real amount: Api.parseAmount(amountField.text)
  readonly property real price: Api.parseAmount(priceField.text)
  readonly property var day: {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateField.text.trim())
    if (!m) return null
    var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 12, 0, 0)
    return isNaN(d.getTime()) || d.getTime() > Date.now() + 86400000 ? null : d
  }
  readonly property bool ok: amount > 0 && price >= 0 && !isNaN(price) && day !== null

  function reset(c) {
    coin = c
    side = "buy"
    amountField.text = ""
    priceField.text = c && !isNaN(c.price) ? Api.editable(c.price) : ""
    dateField.text = Api.isoDay(Date.now())
  }

  function focusAmount() { Qt.callLater(function () { amountField.input.forceActiveFocus() }) }

  function save() {
    if (!ok || !coin) return
    // Today keeps the time it was entered, so two of today's trades still sort.
    var ts = Api.isoDay(Date.now()) === dateField.text.trim() ? Date.now() : day.getTime()
    app.store.addTx(coin, { side: side, amount: amount, price: price, cur: app.currency, ts: ts })
    done()
  }

  Rectangle {
    anchors.fill: parent
    color: "#000000"
    opacity: 0.45
    MouseArea { anchors.fill: parent; onClicked: root.done() }
  }

  Rectangle {
    id: card
    width: root.app.compact ? root.width : Math.min(420, root.width - 48)
    height: form.implicitHeight + 32
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.app.compact ? root.height - height : (root.height - height) / 2
    radius: root.app.ui.radius + 4
    color: root.app.ui.bg
    border.width: root.app.compact ? 0 : 1
    border.color: root.app.ui.border
    MouseArea { anchors.fill: parent }

    Column {
      id: form
      x: 16
      y: 16
      width: parent.width - 32
      spacing: 12

      Row {
        spacing: 10
        CoinLogo {
          anchors.verticalCenter: parent.verticalCenter
          app: root.app
          size: 28
          source: root.coin ? root.coin.image || "" : ""
          symbol: root.coin ? root.coin.symbol || "" : ""
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Add " + (root.coin ? root.coin.name : "") + " transaction"
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.lg
          font.weight: Font.DemiBold
        }
      }

      Row {
        id: sides
        width: parent.width
        spacing: 8
        Chip {
          width: (sides.width - sides.spacing) / 2
          app: root.app
          text: "Buy"
          selected: root.side === "buy"
          onClicked: root.side = "buy"
        }
        Chip {
          width: (sides.width - sides.spacing) / 2
          app: root.app
          text: "Sell"
          selected: root.side === "sell"
          onClicked: root.side = "sell"
        }
      }

      Field {
        id: amountField
        width: parent.width
        app: root.app
        label: "Amount"
        placeholder: "0.00"
        suffix: root.coin ? root.coin.symbol : ""
        valid: text === "" || root.amount > 0
        onAccepted: priceField.input.forceActiveFocus()
      }
      Field {
        id: priceField
        width: parent.width
        app: root.app
        label: "Price per coin"
        suffix: root.app.currency.toUpperCase()
        valid: text === "" || root.price >= 0
        onAccepted: dateField.input.forceActiveFocus()
      }
      Field {
        id: dateField
        width: parent.width
        app: root.app
        label: "Date (YYYY-MM-DD)"
        numeric: false
        valid: root.day !== null
        onAccepted: root.save()
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.amount > 0 && root.price >= 0 ? "Total " + Api.price(root.amount * root.price, root.app.currency) : " "
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }

      Row {
        id: buttons
        width: parent.width
        spacing: 8
        Chip {
          width: (buttons.width - buttons.spacing) / 2
          app: root.app
          text: "Cancel"
          onClicked: root.done()
        }
        Chip {
          width: (buttons.width - buttons.spacing) / 2
          app: root.app
          text: "Save"
          selected: root.ok
          opacity: root.ok ? 1 : 0.5
          onClicked: root.save()
        }
      }
    }
  }
}
