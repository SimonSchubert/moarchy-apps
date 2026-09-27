import QtQuick

// A list model that follows a plain array by key, for a ListView or GridView.
//
// Handing a view a JS array resets it on every assignment: each delegate is
// thrown away and built again, the list jumps back to its top, and the row
// under a finger is a different row. The task list is a new array on every
// tick, so that would be a list nobody can scroll or tap.
//
// Here a row that is still there keeps its delegate. Rows that left are
// removed, new ones inserted and moved ones moved, and the rest only see new
// data: a delegate reads it as `keyed.at(key)`.
ListModel {
  id: root

  property var items: []

  // An app by its key, a process by its pid.
  function keyOf(m, i) {
    if (!m) return "#" + i
    if (m.key) return String(m.key)
    if (m.id) return String(m.id)
    return "#" + i
  }

  property var byKey: ({})
  // The keys in the model's order, so a sync never has to call get().
  property var order: []

  function at(key) { return byKey[key] || ({}) }

  onItemsChanged: sync()

  function sync() {
    var list = items || []
    var keys = []
    var map = {}
    for (var i = 0; i < list.length; i++) {
      var k = keyOf(list[i], i)
      // The same key twice in one list keeps both rows.
      while (map[k] !== undefined) k += "'"
      keys.push(k)
      map[k] = list[i]
    }

    var ord = order
    for (var r = ord.length - 1; r >= 0; r--) {
      if (map[ord[r]] !== undefined) continue
      remove(r)
      ord.splice(r, 1)
    }
    for (var n = 0; n < keys.length; n++) {
      if (ord[n] === keys[n]) continue
      var from = ord.indexOf(keys[n], n + 1)
      if (from >= 0) {
        move(from, n, 1)
        ord.splice(n, 0, ord.splice(from, 1)[0])
      } else {
        insert(n, { key: keys[n] })
        ord.splice(n, 0, keys[n])
      }
    }
    order = ord
    byKey = map
  }
}
