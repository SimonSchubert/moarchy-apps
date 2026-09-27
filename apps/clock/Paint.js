// A colour at an opacity, as the CSS string a Canvas strokes with.
//
// Canvas has no dependency tracking and takes its styles as strings, so the
// dial and the rings build theirs here rather than handing it a QML colour.
.pragma library

function css(c, a) {
  var x = Qt.color(c)
  return "rgba(" + Math.round(x.r * 255) + "," + Math.round(x.g * 255) + ","
    + Math.round(x.b * 255) + "," + (a === undefined ? x.a : a) + ")"
}
