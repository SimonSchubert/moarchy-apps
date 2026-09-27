import QtQuick
import "Minesweeper.js" as M

// The minefield. A covered cell is a lid that stands off the window, lit
// along its top edge; an opened one is a pit very close to the window it sits
// in. The gap between the two is the whole readability of the board.
//
// A press opens, a hold does the other thing -- flags, or opens when the flag
// button is latched -- so no press in this game does nothing and no mode
// cannot reach an action. A tap on a number whose flags add up clears round
// it. On a desktop the right button flags, and a cursor follows the keys.
Item {
  id: root
  property var app
  property var game: null
  // Bumped whenever `game` changed in place, which a binding cannot see.
  property int revision: 0
  // The keyboard's cell, or -1.
  property int cursor: -1

  signal pressed(int cell)
  signal held(int cell)

  readonly property var level: game ? game.level : M.levelFor("standard")
  readonly property real cell: Math.max(18, Math.floor(Math.min(width / level.width, height / level.height)))
  readonly property real gap: Math.max(2, Math.round(cell * 0.07))
  readonly property bool over: revision >= 0 && game !== null && M.isOver(game)
  readonly property bool lost: revision >= 0 && game !== null && M.lost(game)
  readonly property bool won: revision >= 0 && game !== null && M.won(game)
  readonly property var wrong: {
    var r = revision
    var out = ({})
    if (game && over) {
      var list = M.wrongFlags(game)
      for (var i = 0; i < list.length; i++) out[list[i]] = true
    }
    return out
  }

  Grid {
    id: grid
    anchors.centerIn: parent
    columns: root.level.width
    Repeater {
      model: M.cellCount(root.level)
      delegate: Item {
        id: sq
        required property int index
        width: root.cell
        height: root.cell

        readonly property bool open: root.revision >= 0 && !!(root.game && root.game.opened[index])
        readonly property bool flag: root.revision >= 0 && !!(root.game && root.game.flags[index])
        readonly property bool mine: root.over && M.isMine(root.game, index)
        readonly property bool boom: root.revision >= 0 && !!root.game && root.game.boom === index
        // A won board flags the mines it never needed flagging: the picture
        // of a finished board should be a finished board.
        readonly property bool shownFlag: flag || (root.won && mine)
        // Every mine still in the ground once one has gone off.
        readonly property bool shownMine: (open && mine) || (root.lost && mine && !flag)
        readonly property int number: open && !mine && root.game ? M.count(root.game, index) : 0
        readonly property bool pit: open || (root.lost && mine && !flag)

        Accessible.role: Accessible.Button
        Accessible.name: open ? (number ? String(number) : "open") : shownFlag ? "flagged" : "covered"

        Rectangle {
          id: face
          x: root.gap / 2
          y: root.gap / 2
          width: parent.width - root.gap
          height: parent.height - root.gap
          radius: Math.max(3, root.cell * 0.14)
          color: sq.boom ? root.app.ui.boom : sq.pit ? root.app.ui.pit
            : mouse.pressed ? Qt.darker(root.app.ui.lid, 1.08)
            : mouse.containsMouse ? Qt.tint(root.app.ui.lid, root.app.ui.hover) : root.app.ui.lid
          border.width: root.cursor === sq.index ? 2 : 0
          border.color: root.app.ui.accent

          // One light source, top left: what makes a flat square read as
          // something raised rather than as a lighter square.
          Rectangle {
            visible: !sq.pit
            x: face.radius
            y: 1
            width: parent.width - face.radius * 2
            height: 1
            color: root.app.ui.lidTop
          }
          Rectangle {
            visible: !sq.pit
            x: 1
            y: face.radius
            width: 1
            height: parent.height - face.radius * 2
            color: root.app.ui.lidTop
          }
        }

        Text {
          anchors.centerIn: parent
          visible: sq.number > 0
          text: sq.number
          color: root.app.ui.numbers[Math.max(1, Math.min(sq.number, 8)) - 1]
          font.family: root.app.ui.font
          font.pixelSize: Math.round(root.cell * 0.56)
          font.weight: Font.Bold
        }

        // A mine: a disc with four spikes through it and one glint.
        Item {
          anchors.centerIn: parent
          visible: sq.shownMine
          width: root.cell * 0.5
          height: width
          Repeater {
            model: [0, 45, 90, 135]
            delegate: Rectangle {
              required property var modelData
              anchors.centerIn: parent
              width: parent.width * 1.1
              height: Math.max(1.5, root.cell * 0.06)
              rotation: modelData
              color: sq.boom ? root.app.ui.inkOnAccent : root.app.ui.mine
            }
          }
          Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.66
            height: width
            radius: width / 2
            color: sq.boom ? root.app.ui.inkOnAccent : root.app.ui.mine
            Rectangle {
              x: parent.width * 0.18
              y: parent.height * 0.16
              width: parent.width * 0.26
              height: width
              radius: width / 2
              color: root.app.ui.lidTop
            }
          }
        }

        // A flag: a pole, a foot and a pennant. A shape, because a red square
        // and a grey one are the same square to a lot of people.
        Item {
          anchors.fill: parent
          visible: sq.shownFlag && !sq.open
          Rectangle {
            x: parent.width * 0.38
            y: parent.height * 0.22
            width: Math.max(1.5, root.cell * 0.075)
            height: parent.height * 0.56
            color: root.app.ui.pole
          }
          Rectangle {
            x: parent.width * 0.24
            y: parent.height * 0.76
            width: parent.width * 0.36
            height: Math.max(1.5, root.cell * 0.075)
            color: root.app.ui.pole
          }
          Canvas {
            id: pennant
            x: parent.width * 0.38
            y: parent.height * 0.22
            width: parent.width * 0.34
            height: parent.height * 0.26
            property color ink: root.app.ui.flag
            onInkChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.fillStyle = ink
              ctx.beginPath()
              ctx.moveTo(0, 0)
              ctx.lineTo(width, height / 2)
              ctx.lineTo(0, height)
              ctx.closePath()
              ctx.fill()
            }
          }
        }

        // A flag with no mine under it, once it is over: "you were sure about
        // this one and you were wrong", which is the most useful thing a lost
        // board has to say.
        Repeater {
          model: root.wrong[sq.index] ? [45, -45] : []
          delegate: Rectangle {
            required property var modelData
            anchors.centerIn: parent
            width: root.cell * 0.8
            height: Math.max(2, root.cell * 0.09)
            radius: height / 2
            rotation: modelData
            color: root.app.ui.wrong
          }
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: !root.app.compact
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          // Shorter than Qt's 800 ms: a flag is the commonest hold in the
          // game, and seconds of a game spent waiting for one add up.
          pressAndHoldInterval: 380
          property bool heldDown: false
          onPressed: heldDown = false
          onPressAndHold: { heldDown = true; root.held(sq.index) }
          onClicked: function (event) {
            if (heldDown) return
            if (event.button === Qt.RightButton) root.held(sq.index)
            else root.pressed(sq.index)
          }
        }
      }
    }
  }
}
