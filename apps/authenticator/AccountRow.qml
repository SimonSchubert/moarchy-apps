import QtQuick
import "kit"
import "Otp.js" as Otp

// One account: whose it is, and its code, big, with the time it has left.
// A tap copies the code -- the only thing anybody opens this app to do -- and
// the pencil (or a long press, or a right click) opens the account itself.
Rectangle {
  id: root
  property var app
  property var account: null
  // Where the keyboard is, on a desktop.
  property bool current: false
  // Codes hidden until tapped (Settings), and this one tapped.
  property bool hidden: false
  signal clicked()
  signal edit()

  readonly property int period: account && account.period ? account.period : Otp.DEFAULT_PERIOD
  readonly property int remaining: Otp.remainingAt(app.now, period)
  // The code only changes when the counter does, so it is worked out once a
  // period rather than once a second: a property only notifies on a change.
  readonly property int counter: Otp.counterAt(app.now, period)
  readonly property string code: Otp.codeFor(account, counter)
  readonly property bool late: remaining <= 5
  readonly property string next: late && !hidden ? Otp.codeFor(account, counter + 1) : ""

  implicitHeight: app.compact ? 80 : 86
  radius: app.ui.radius
  color: mouse.pressed ? app.ui.pressed : mouse.containsMouse ? app.ui.hover : app.compact ? "transparent" : app.ui.surface
  border.width: app.compact ? 0 : 1
  border.color: current ? app.ui.accent : app.ui.line
  Accessible.role: Accessible.Button
  Accessible.name: Otp.title(account) + ", " + (hidden ? "hidden" : code.split("").join(" "))

  Rectangle {
    id: tile
    x: root.app.compact ? 12 : 16
    anchors.verticalCenter: parent.verticalCenter
    width: 40
    height: 40
    radius: root.app.ui.radius
    readonly property color hue: root.app.ui.accountHue(root.account ? root.account.issuer || root.account.name : "")
    color: root.app.alpha(hue, 0.18)
    Text {
      anchors.centerIn: parent
      text: Otp.monogram(root.account)
      color: tile.hue
      font.family: root.app.ui.font
      font.pixelSize: 17
      font.weight: Font.Bold
    }
  }

  Column {
    anchors.left: tile.right
    anchors.leftMargin: 12
    anchors.right: ring.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Row {
      width: parent.width
      spacing: 8
      Text {
        id: issuer
        width: Math.min(implicitWidth, parent.width * (who.text ? 0.62 : 1))
        text: Otp.title(root.account)
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
        font.weight: Font.Bold
        elide: Text.ElideRight
      }
      Text {
        id: who
        width: parent.width - issuer.width - parent.spacing
        text: Otp.subtitle(root.account)
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
        elide: Text.ElideRight
      }
    }
    Row {
      spacing: 12
      Text {
        id: big
        text: root.hidden ? Otp.grouped(root.app.dots(root.code.length)) : Otp.grouped(root.code)
        color: root.hidden ? root.app.ui.muted : root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.xl + 2
        font.weight: Font.Bold
        font.letterSpacing: 1
      }
      Text {
        visible: root.next !== ""
        anchors.baseline: big.baseline
        text: "next " + Otp.grouped(root.next)
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: root.app.ui.fs.sm
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: !root.app.compact
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function (event) {
      if (event.button === Qt.RightButton) root.edit()
      else root.clicked()
    }
    onPressAndHold: root.edit()
  }

  Ring {
    id: ring
    anchors.right: pencil.left
    anchors.rightMargin: root.app.compact ? 2 : 8
    anchors.verticalCenter: parent.verticalCenter
    app: root.app
    remaining: root.remaining
    period: root.period
  }

  IconButton {
    id: pencil
    anchors.right: parent.right
    anchors.rightMargin: root.app.compact ? 0 : 6
    anchors.verticalCenter: parent.verticalCenter
    app: root.app
    glyph: root.app.glyphs.edit
    color: root.app.ui.muted
    size: 18
    label: "Edit " + Otp.title(root.account)
    onClicked: root.edit()
  }
}
