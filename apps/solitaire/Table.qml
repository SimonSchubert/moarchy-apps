import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Klondike.js" as K
import "Layout.js" as L

// The table: seven columns, the stock, the waste and four foundations, drawn
// from Layout.js -- the same arithmetic that says which card a tap is on.
//
// One delegate per card, all fifty-two of them always, each placed from the
// table. A move is the table changing, so every card that moved glides to its
// new place on its own; nothing here knows what a move is.
//
// A tap is the game: it goes to the window, which knows the rules. With a
// mouse a run can also be dragged, and dropped anywhere over the column or
// foundation it should land on.
Item {
  id: root
  property var app
  property var table: null
  // [pile, position] of the run picked up and waiting for a second tap.
  property var selected: null
  property var drops: []
  // The height the table is shown in: the squeeze is fitted to it.
  property real viewHeight: height

  signal tapped(int pile, int position)
  signal dropped(int pile, int position, int target)

  readonly property var layout: table ? L.layoutFor(width, viewHeight, table) : null
  implicitHeight: table && layout ? L.heightOf(layout, table) : 0

  // Where every card is: index by card, {x, y, z, shown, faceUp, full}.
  readonly property var places: {
    var out = []
    var t = table, l = layout
    if (!t || !l) return out
    function put(card, r, z, shown, faceUp, full) {
      out[card] = { x: r.x, y: r.y, z: z, shown: shown, faceUp: faceUp, full: full }
    }
    for (var i = 0; i < t.stock.length; i++)
      put(t.stock[i], L.cardAt(l, t, K.STOCK, 0), i, i === t.stock.length - 1, false, false)
    var fanned = Math.min(t.waste.length, t.draw)
    for (var w = 0; w < t.waste.length; w++)
      put(t.waste[w], L.cardAt(l, t, K.WASTE, w), 100 + w, w >= t.waste.length - fanned, true, w === t.waste.length - 1)
    for (var s = 0; s < K.SUITS; s++)
      for (var r = 0; r < t.up[s]; r++)
        put(r * K.SUITS + s, L.cardAt(l, t, K.FOUNDATION + s, r), 200 + r, r === t.up[s] - 1, true, true)
    for (var c = 0; c < K.COLUMNS; c++) {
      var pile = K.TABLEAU + c
      var col = t.piles[c]
      for (var p = 0; p < col.length; p++)
        put(col[p], L.cardAt(l, t, pile, p), 300 + p, true, p >= t.down[c], p === col.length - 1)
    }
    return out
  }

  // The cards travelling with the pointer, by card.
  property var dragged: ({})
  property real dragDx: 0
  property real dragDy: 0
  readonly property bool dragging: Object.keys(dragged).length > 0

  // ------------------------------------------------------------ the felt

  // Empty piles: a hole in the baize rather than a card that is not there,
  // with the suit a foundation takes shown faintly -- four identical holes
  // are no help to somebody placing the first ace of the game.
  Repeater {
    model: root.layout ? K.PILES : 0
    delegate: Rectangle {
      id: slot
      required property int index
      readonly property var r: L.cardAt(root.layout, root.table, index, 0)
      visible: index !== K.WASTE || root.table.waste.length === 0
      x: r.x
      y: r.y
      width: r.w
      height: r.h
      radius: root.app.ui.radius > 0 ? width * 0.12 : 2
      color: root.app.ui.slot
      Pip {
        visible: K.isFoundation(slot.index)
        anchors.centerIn: parent
        suit: slot.index - K.FOUNDATION
        size: slot.height * 0.2
        color: root.app.ui.slotInk
      }
      // An empty stock with a waste to turn back over.
      Icon {
        visible: slot.index === K.STOCK && root.table.stock.length === 0 && root.table.waste.length > 0
        anchors.centerIn: parent
        app: root.app
        text: KG.refresh
        size: Math.round(slot.width * 0.5)
        color: root.app.ui.slotInk
      }
    }
  }

  // ------------------------------------------------------------ the cards

  Repeater {
    model: root.layout ? K.DECK : 0
    delegate: PlayingCard {
      id: face
      required property int index
      readonly property var place: root.places[index] || ({ x: 0, y: 0, z: 0, shown: false, faceUp: false, full: false })
      readonly property bool carried: root.dragged[index] === true
      readonly property bool moving: xAnim.running || yAnim.running
      app: root.app
      card: index
      faceUp: place.faceUp
      full: place.full
      visible: place.shown || moving || carried
      width: root.layout.cardW
      height: root.layout.cardH
      x: place.x + (carried ? root.dragDx : 0)
      y: place.y + (carried ? root.dragDy : 0)
      z: place.z + (moving || carried ? 1000 : 0)
      Behavior on x { enabled: !face.carried; NumberAnimation { id: xAnim; duration: 170; easing.type: Easing.OutCubic } }
      Behavior on y { enabled: !face.carried; NumberAnimation { id: yAnim; duration: 170; easing.type: Easing.OutCubic } }
    }
  }

  // ------------------------------------------------------------ rings

  // The run picked up, and everywhere it may go.
  Rectangle {
    readonly property var run: root.selected && root.table ? K.runFrom(root.table, root.selected[0], root.selected[1]) : []
    readonly property var first: run.length ? L.cardAt(root.layout, root.table, root.selected[0], root.selected[1]) : null
    readonly property var last: run.length ? L.cardAt(root.layout, root.table, root.selected[0], root.selected[1] + run.length - 1) : null
    visible: run.length > 0
    z: 2000
    x: first ? first.x - 1 : 0
    y: first ? first.y - 1 : 0
    width: first ? first.w + 2 : 0
    height: first && last ? last.y + last.h - first.y + 2 : 0
    radius: root.app.ui.radius > 0 ? width * 0.12 : 2
    color: "transparent"
    border.width: 3
    border.color: root.app.ui.pick
  }
  Repeater {
    model: root.drops
    delegate: Rectangle {
      required property var modelData
      readonly property var r: L.cardAt(root.layout, root.table, modelData, Math.max(K.cardsIn(root.table, modelData) - 1, 0))
      z: 2000
      x: r.x - 1
      y: r.y - 1
      width: r.w + 2
      height: r.h + 2
      radius: root.app.ui.radius > 0 ? width * 0.12 : 2
      color: root.app.ui.alpha(root.app.ui.pick, 0.14)
      border.width: 2.5
      border.color: root.app.ui.drop
    }
  }

  // ------------------------------------------------------------ input

  MouseArea {
    id: mouse
    anchors.fill: parent
    z: 3000
    hoverEnabled: !root.app.compact
    property var hit: null
    property real startX: 0
    property real startY: 0
    cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

    onPressed: function (event) {
      hit = root.layout ? L.pileAt(root.layout, root.table, event.x, event.y) : null
      startX = event.x
      startY = event.y
    }
    onPositionChanged: function (event) {
      if (!pressed || !hit) return
      if (!root.dragging) {
        if (Math.abs(event.x - startX) + Math.abs(event.y - startY) < 10) return
        if (hit[0] === K.STOCK) return
        var run = K.runFrom(root.table, hit[0], hit[1])
        if (!run.length || !K.destinations(root.table, hit[0], hit[1]).length) return
        var d = ({})
        for (var i = 0; i < run.length; i++) d[run[i]] = true
        root.dragged = d
      }
      root.dragDx = event.x - startX
      root.dragDy = event.y - startY
    }
    onReleased: function (event) {
      if (root.dragging) {
        var target = L.dropAt(root.layout, event.x, event.y)
        var from = hit
        root.dragged = ({})
        root.dragDx = 0
        root.dragDy = 0
        if (target >= 0) root.dropped(from[0], from[1], target)
        return
      }
      if (hit) root.tapped(hit[0], hit[1])
    }
    onCanceled: { root.dragged = ({}); root.dragDx = 0; root.dragDy = 0 }
  }
}
