import QtQuick
import "Api.mjs" as Api

// Where the price sits between the day's low and high.
Column {
  id: root
  property var app
  property real low: NaN
  property real high: NaN
  property real value: NaN
  property string currency: "usd"
  property string title: "24h range"

  readonly property real ratio: isNaN(low) || isNaN(high) || high <= low || isNaN(value)
    ? NaN : Math.max(0, Math.min(1, (value - low) / (high - low)))

  spacing: 6

  Text {
    text: root.title
    color: root.app.ui.muted
    font.family: root.app.ui.font
    font.pixelSize: root.app.ui.fs.xs
  }

  Item {
    width: parent.width
    height: 8
    Rectangle {
      anchors.fill: parent
      radius: 4
      color: root.app.ui.surfaceHigh
    }
    Rectangle {
      visible: !isNaN(root.ratio)
      width: Math.max(8, parent.width * (isNaN(root.ratio) ? 0 : root.ratio))
      height: parent.height
      radius: 4
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: root.app.ui.down }
        GradientStop { position: 1; color: root.app.ui.up }
      }
    }
  }

  Item {
    width: parent.width
    height: lowText.implicitHeight
    Text {
      id: lowText
      text: Api.price(root.low, root.currency)
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
    }
    Text {
      anchors.right: parent.right
      text: Api.price(root.high, root.currency)
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.ui.fs.xs
    }
  }
}
