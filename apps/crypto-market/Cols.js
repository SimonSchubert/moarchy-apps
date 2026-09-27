.pragma library

// Which columns a coin list has room for, shared by the rows and the header
// above them so the two always agree.
function layout(width) {
  var compact = width < 560
  return {
    compact: compact,
    rank: !compact,
    spark: compact ? width >= 400 : width >= 1000,
    h1: !compact && width >= 640,
    d7: !compact,
    vol: !compact && width >= 900,
    mcap: !compact && width >= 760,
    price: compact ? 104 : 116,
    pct: 68,
    money: 118,
    sparkW: compact ? 60 : 112
  }
}

// Sorted copy of a coin list. Coins missing the figure go last whichever way
// round, so a descending sort by volume does not open on a column of dashes.
function sorted(rows, key, descending) {
  if (!rows || key === "custom" || key === "rank" && !descending) return rows || []
  var out = rows.slice()
  out.sort(function (a, b) {
    if (key === "name") {
      var c = String(a.name).toLowerCase() < String(b.name).toLowerCase() ? -1 : 1
      return descending ? -c : c
    }
    var x = a[key], y = b[key]
    var xn = x === undefined || x === null || isNaN(x), yn = y === undefined || y === null || isNaN(y)
    if (xn || yn) return xn === yn ? 0 : xn ? 1 : -1
    return descending ? y - x : x - y
  })
  return out
}
