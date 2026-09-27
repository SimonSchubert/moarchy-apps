import QtQuick
import "Api.mjs" as Api

// Coin to money and back. Whichever side was typed in last is the one kept
// when the price moves.
Rectangle {
  id: root
  property var app
  property string symbol: ""
  property real price: NaN
  property string currency: "usd"
  property string lastEdited: "coin"

  implicitHeight: col.implicitHeight + 24
  radius: app.ui.radius
  color: app.ui.surface

  function sync() {
    if (isNaN(price) || price <= 0) return
    if (lastEdited === "coin") {
      var c = Api.parseAmount(coinField.text)
      if (!coinField.input.activeFocus || !isNaN(c)) fiatField.text = isNaN(c) ? "" : Api.editable(c * price)
    } else {
      var f = Api.parseAmount(fiatField.text)
      if (!fiatField.input.activeFocus || !isNaN(f)) coinField.text = isNaN(f) ? "" : Api.editable(f / price)
    }
  }
  onPriceChanged: sync()
  Component.onCompleted: { coinField.text = "1"; sync() }

  Column {
    id: col
    x: 12
    y: 12
    width: parent.width - 24
    spacing: 10

    Text {
      text: "Converter"
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.md
      font.weight: Font.DemiBold
    }
    Field {
      id: coinField
      width: parent.width
      app: root.app
      suffix: root.symbol
      valid: text === "" || !isNaN(Api.parseAmount(text))
      onEdited: { root.lastEdited = "coin"; root.sync() }
    }
    Field {
      id: fiatField
      width: parent.width
      app: root.app
      suffix: Api.currency(root.currency).code.toUpperCase()
      valid: text === "" || !isNaN(Api.parseAmount(text))
      onEdited: { root.lastEdited = "fiat"; root.sync() }
    }
  }
}
