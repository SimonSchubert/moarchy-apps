import QtQuick
import "Breakout.js" as B

// The field: the wall, the bat and the ball, placed by one multiplication.
//
// Everything the world knows is in widths, so this works out one number --
// the pixels in a width -- and multiplies by it. A window wider than the
// field is tall gets a narrower field rather than a stretched one, because a
// stretched Breakout is a different game.
//
// Plain rectangles rather than a Canvas: fifty-six of them that change only
// when a brick is hit, and two that move. A Canvas repainted sixty times a
// second is the thing a PinePhone's GPU has least of.
//
// The bat follows a finger absolutely, from anywhere on the field: a press
// puts the middle of the bat there, a slide moves it, and the same press
// serves the ball. On a desktop the pointer moves it without a press.
Item {
  id: root
  property var app      // Panel: the tokens, and the game

  readonly property real across: Math.max(0, Math.min(width, height / B.HEIGHT))
  readonly property real ox: (width - across) / 2
  readonly property real oy: (height - across * B.HEIGHT) / 2
  function px(v) { return v * across }

  Accessible.role: Accessible.Canvas
  Accessible.name: app.dead ? "Field, game over, " + app.score + " points"
    : "Field, " + app.standing + " bricks left, " + app.lives + " lives, " + app.score + " points"

  Rectangle {
    id: field
    x: root.ox
    y: root.oy
    width: root.across
    height: root.across * B.HEIGHT
    radius: root.app.ui.radius
    color: root.app.ui.field
    border.width: 1
    border.color: root.app.ui.line
    clip: true

    Repeater {
      model: B.COLUMNS * B.ROWS
      delegate: Rectangle {
        id: brick
        required property int index
        readonly property int hits: root.app.bricks[index] || 0
        readonly property var r: B.brickRect(index)
        readonly property real gap: B.BRICK_W * 0.10
        visible: hits > 0
        x: root.px(r.x + gap / 2)
        y: root.px(r.y + gap / 4)
        width: root.px(r.w - gap)
        height: root.px(r.h - gap / 2)
        // Square as the rest of the app is, unless the theme rounds.
        radius: root.app.ui.radius > 0 ? root.px(B.BRICK_H * 0.22) : 0
        color: root.app.ui.rows[Math.floor(index / B.COLUMNS) % root.app.ui.rows.length]

        // The groove that says this one is not done yet: one per hit still
        // owed, in the field's own colour, so it reads as an absence. Hue
        // cannot also carry how tough a brick is.
        Repeater {
          model: Math.min(Math.max(brick.hits - 1, 0), 2)
          delegate: Rectangle {
            required property int index
            // In widths, from the cell's corner, as the GTK version drew it.
            readonly property real inset: brick.gap * 0.9 + index * B.BRICK_H * 0.22
            x: root.px(inset - brick.gap / 2)
            y: root.px(inset * 0.55 - brick.gap / 4)
            width: root.px(brick.r.w - inset * 2)
            height: root.px(brick.r.h - inset * 1.1)
            radius: brick.radius
            color: "transparent"
            border.width: Math.max(1, root.px(B.BRICK_H * 0.10))
            border.color: root.app.ui.field
          }
        }
      }
    }

    // The bat, with a light line along its top edge.
    Rectangle {
      x: root.px(root.app.bat - B.BAT_W / 2)
      y: root.px(B.BAT_Y - B.BAT_H / 2)
      width: root.px(B.BAT_W)
      height: root.px(B.BAT_H)
      radius: root.app.ui.round(height)
      color: root.app.ui.bat
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.32 - height / 2
        width: parent.width * 0.7
        height: Math.max(1, parent.height * 0.16)
        radius: root.app.ui.round(height)
        color: root.app.ui.batRim
      }
    }

    Rectangle {
      x: root.px(root.app.ballX - B.BALL)
      y: root.px(root.app.ballY - B.BALL)
      width: root.px(B.BALL * 2)
      height: width
      radius: width / 2
      color: root.app.ui.ball
      border.width: Math.max(1, width * 0.08)
      border.color: root.app.ui.ballRim
    }

    // What to do next, where the person is looking: on the field, under the
    // bat, while the game waits for them.
    Text {
      visible: !root.app.served && !root.app.dead
      anchors.horizontalCenter: parent.horizontalCenter
      // Its foot a little under the bat, as the GTK version set it.
      y: root.px(B.BAT_Y + 0.066) - height
      text: !root.app.readyToServe ? "Ready…"
        : root.app.compact ? "Tap to serve" : "Click to serve"
      color: root.app.ui.muted
      font.family: root.app.ui.font
      font.pixelSize: Math.max(11, root.px(0.038))
      font.weight: Font.Bold
    }

    // Paused, or over, said on the field rather than beside it.
    Column {
      visible: (root.app.paused && root.app.served) || root.app.dead
      anchors.centerIn: parent
      spacing: 6
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.app.dead ? "Game over" : "Paused"
        color: root.app.ui.text
        font.family: root.app.ui.font
        font.pixelSize: Math.max(18, root.px(0.075))
        font.weight: Font.Bold
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.app.dead ? root.app.score + " points"
          : root.app.compact ? "Tap to go on" : "Space to go on"
        color: root.app.ui.muted
        font.family: root.app.ui.font
        font.pixelSize: Math.max(12, root.px(0.042))
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    // On a desktop the pointer is the bat; on a phone there is no pointer.
    hoverEnabled: !root.app.compact
    cursorShape: root.app.compact ? Qt.ArrowCursor : Qt.BlankCursor
    function toWidths(mx) { return root.across > 0 ? (mx - root.ox) / root.across : B.WIDTH / 2 }
    // A press is also a launch: a tap and the first frame of a drag are the
    // same gesture on a touch screen.
    onPressed: function (mouse) {
      root.app.aimAt(toWidths(mouse.x))
      root.app.press()
    }
    onPositionChanged: function (mouse) {
      if (pressed || containsMouse) root.app.aimAt(toWidths(mouse.x))
    }
  }
}
