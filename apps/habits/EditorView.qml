import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Habits.js" as H

// Making a habit, and changing one. One page does both, because the fields
// are the same and a separate "new" form is a second place for the frequency
// rules to drift. A page rather than a dialog: on a phone the fields have to
// scroll above the keyboard, which a sheet from the bottom cannot do.
Item {
  id: root
  property var app
  // The habit being changed, or null for a new one.
  property var habit: null
  readonly property bool isNew: habit === null

  property string kind: habit ? habit.kind : H.BOOLEAN
  property int frequency: habit ? H.frequencyIndex(habit) : 0
  property string colour: habit ? habit.colour : "green"
  readonly property bool valid: nameField.text.trim() !== ""

  function save() {
    if (!valid) { nameField.takeFocus(); return }
    app.saveHabit(habit, {
      name: nameField.text,
      question: questionField.text,
      kind: kind,
      target: parseFloat(targetField.text),
      unit: unitField.text,
      frequency: frequency,
      colour: colour
    })
  }

  PageHeader {
    id: head
    app: root.app
    width: parent.width
    title: root.isNew ? "New habit" : "Edit habit"
    Button {
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      primary: true
      enabled: root.valid
      text: root.isNew ? "Add" : "Save"
      onClicked: root.save()
    }
  }

  Flickable {
    id: flick
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: body.implicitHeight + 48
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      x: root.app.ui.gutter
      y: 4
      width: Math.min(flick.width - x * 2, 560)
      spacing: 20

      TextField {
        id: nameField
        app: root.app
        width: parent.width
        label: "Name"
        placeholder: "Read, Water, Exercise…"
        text: root.habit ? root.habit.name : ""
        onAccepted: root.save()
      }

      TextField {
        id: questionField
        app: root.app
        width: parent.width
        label: "Question (optional)"
        placeholder: "Did you read today?"
        text: root.habit ? root.habit.question : ""
        onAccepted: root.app.resetFocus()
      }

      SettingsSection {
        app: root.app
        width: parent.width
        title: "Records"
        Row {
          spacing: 8
          Chip { app: root.app; text: "Yes or no"; selected: root.kind === H.BOOLEAN; onClicked: root.kind = H.BOOLEAN }
          Chip { app: root.app; text: "A number"; selected: root.kind === H.MEASURABLE; onClicked: root.kind = H.MEASURABLE }
        }
      }

      Row {
        visible: root.kind === H.MEASURABLE
        width: parent.width
        spacing: 12
        TextField {
          id: targetField
          app: root.app
          width: (parent.width - 12) / 2
          label: "Target each day"
          placeholder: "8"
          inputHints: Qt.ImhDigitsOnly
          text: root.habit && root.habit.kind === H.MEASURABLE ? String(root.habit.target) : "1"
          onAccepted: root.app.resetFocus()
        }
        TextField {
          id: unitField
          app: root.app
          width: (parent.width - 12) / 2
          label: "Unit"
          placeholder: "glasses"
          text: root.habit ? root.habit.unit : ""
          onAccepted: root.app.resetFocus()
        }
      }

      SettingsSection {
        app: root.app
        width: parent.width
        title: "How often"
        note: "Three times a week is on track on any day the week behind it holds three."
        Flow {
          width: parent.width
          spacing: 8
          Repeater {
            model: H.FREQUENCIES
            delegate: Chip {
              required property var modelData
              required property int index
              app: root.app
              text: modelData.label
              selected: root.frequency === index
              onClicked: root.frequency = index
            }
          }
        }
      }

      SettingsSection {
        app: root.app
        width: parent.width
        title: "Colour"
        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: H.COLOURS
            delegate: Item {
              id: swatch
              required property var modelData
              readonly property bool chosen: root.colour === modelData.key
              width: 48
              height: 48
              Accessible.role: Accessible.RadioButton
              Accessible.name: modelData.label
              Accessible.checked: chosen
              Rectangle {
                anchors.centerIn: parent
                width: 34
                height: 34
                radius: root.app.ui.radius
                color: root.app.habitHue(swatch.modelData.key)
                border.width: swatch.chosen ? 3 : 0
                border.color: root.app.ui.text
                Icon {
                  anchors.centerIn: parent
                  visible: swatch.chosen
                  app: root.app
                  text: KG.check
                  size: 18
                  color: root.app.ui.bg
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.colour = swatch.modelData.key
              }
            }
          }
        }
      }

      Button {
        visible: !root.isNew
        app: root.app
        text: "Delete habit"
        glyph: KG.remove
        tint: root.app.ui.bad
        active: true
        onClicked: root.app.askDelete(root.habit)
      }
    }
  }
}
