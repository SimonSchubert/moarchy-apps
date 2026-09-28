// The switch on an alarm.
//
// Not the kit's Check, which is a tick box, and the difference is not
// decoration: a tick box says *this one is selected* and a switch says *this
// one is on*. An alarm is the second, and it is the one control on the screen
// somebody uses without reading anything, so it has to be the shape their
// thumb already knows.
//
// The kit's Toggle is a switch with a label beside it, for Settings; this one
// is the bare switch at the end of a row, with the whole row as its label.
import QtQuick

Item {
  id: root

  property bool checked: false
  property color accent: "steelblue"
  property color knobInk: "white"
  property color dim: "grey"
  // The theme's corners: square on Omarchy, a pill where windows are rounded.
  property int corner: 0

  signal toggled(bool checked)

  implicitWidth: 52
  implicitHeight: 44
  width: implicitWidth
  height: implicitHeight

  Accessible.role: Accessible.Switch
  Accessible.checkable: true
  Accessible.checked: root.checked
  Accessible.onPressAction: root.flip()

  function flip(): void {
    root.toggled(!root.checked)
  }

  Rectangle {
    id: track
    anchors.centerIn: parent
    width: 46
    height: 26
    radius: root.corner > 0 ? height / 2 : 0
    // Off is a filled track one shade darker, not an outlined one. The
    // outline was a 1px border that a phone screen loses outdoors, and a
    // switch whose off state is invisible is a switch with one state.
    color: root.checked ? root.accent : Qt.rgba(root.dim.r, root.dim.g, root.dim.b, 0.34)

    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
      id: knob
      width: 20
      height: 20
      radius: root.corner > 0 ? height / 2 : 0
      y: (parent.height - height) / 2
      x: root.checked ? parent.width - width - 3 : 3
      color: root.checked ? root.knobInk : root.dim

      Behavior on x {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
      Behavior on color { ColorAnimation { duration: 120 } }
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.flip()
  }
}
