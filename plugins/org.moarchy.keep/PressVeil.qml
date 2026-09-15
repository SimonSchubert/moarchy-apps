import QtQuick
import qs.Commons

Rectangle {
  id: pv
  property color ink
  property bool on: false
  visible: pv.color.a > 0
  color: Util.alpha(pv.ink, pv.on ? 0.12 : 0)
  Behavior on color {
    enabled: pv.color.a > 0
    ColorAnimation { duration: 120 }
  }
}
