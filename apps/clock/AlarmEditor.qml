import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Alarms.js" as Alarms

// One alarm, being set: the two wheels and what they mean, how often, and
// what it is for. A page over the tab; leaving it any way but Save is a cancel,
// because nothing in the list changes until Save.
Item {
  id: root
  property var app
  readonly property var draft: app.draft

  PageHeader {
    id: head
    app: root.app
    width: parent.width
    title: root.app.draftIsNew ? "New alarm" : "Alarm"
    subtitle: root.app.armed ? "Tap the bin again to delete it" : ""
    IconButton {
      visible: !root.app.draftIsNew
      app: root.app
      glyph: KG.remove
      label: root.app.armed ? "Tap again to delete" : "Delete this alarm"
      color: root.app.armed ? root.app.ui.bad : root.app.ui.text
      active: root.app.armed
      onClicked: root.app.deleteDraft()
    }
    IconButton {
      app: root.app
      glyph: KG.check
      label: "Save this alarm"
      color: root.app.ui.accent
      onClicked: root.app.saveDraft()
    }
  }

  Flickable {
    id: flick
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: body.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      x: root.app.ui.gutter
      y: 4
      width: Math.min(flick.width - x * 2, 560)
      spacing: 14

      // The wheels and the sentence under them are one box, because the
      // sentence is what the wheels mean.
      Card {
        app: root.app
        width: parent.width

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 2

          Wheel {
            anchors.verticalCenter: parent.verticalCenter
            count: root.app.hour24 ? 24 : 12
            from: root.app.hour24 ? 0 : 1
            pad: root.app.hour24
            value: root.app.hour24
              ? (root.draft ? root.draft.hour : 0)
              : (root.draft ? ((root.draft.hour % 12) || 12) : 12)
            ink: root.app.ui.text
            dim: root.app.ui.muted
            family: root.app.ui.font
            radius: root.app.ui.radius
            bodySize: Math.round(root.app.body * 1.5)
            rowHeight: 52
            onPicked: function (n) {
              if (!root.draft) return
              if (root.app.hour24) { root.app.change("hour", n); return }
              var pm = root.draft.hour >= 12
              root.app.change("hour", (n % 12) + (pm ? 12 : 0))
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ":"
            color: root.app.ui.muted
            font.family: root.app.ui.font
            font.pixelSize: Math.round(root.app.body * 1.5)
          }
          Wheel {
            anchors.verticalCenter: parent.verticalCenter
            count: 60
            value: root.draft ? root.draft.minute : 0
            ink: root.app.ui.text
            dim: root.app.ui.muted
            family: root.app.ui.font
            radius: root.app.ui.radius
            bodySize: Math.round(root.app.body * 1.5)
            rowHeight: 52
            onPicked: function (n) { root.app.change("minute", n) }
          }
          // AM and PM are two words, not a wheel of two numbers.
          Column {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.app.hour24
            spacing: 4
            Repeater {
              model: ["AM", "PM"]
              delegate: Chip {
                required property string modelData
                required property int index
                app: root.app
                text: modelData
                selected: root.draft ? ((root.draft.hour >= 12) === (index === 1)) : false
                onClicked: if (root.draft) root.app.change("hour", (root.draft.hour % 12) + (index ? 12 : 0))
              }
            }
          }
        }

        // What setting it will do, said before it is saved: the wheel says
        // 06:30 and this says "tomorrow, in 9 h 20 min".
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: {
            var at = root.app.previewFire()
            return at ? Alarms.whichDay(at, root.app.now) + ", " + Alarms.untilLabel(at - root.app.now) : ""
          }
          color: root.app.ui.accent
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
        }
      }

      Card {
        app: root.app
        width: parent.width
        title: "Repeats"

        Flow {
          width: parent.width
          spacing: 6
          Repeater {
            model: [
              { text: "Once", days: [] },
              { text: "Every day", days: [0, 1, 2, 3, 4, 5, 6] },
              { text: "Weekdays", days: [1, 2, 3, 4, 5] },
              { text: "Weekends", days: [0, 6] }
            ]
            delegate: Chip {
              required property var modelData
              app: root.app
              text: modelData.text
              selected: root.draft ? Alarms.sameDays(root.draft.days, modelData.days) : false
              onClicked: root.app.setRepeat(modelData.days)
            }
          }
        }

        // Sunday and Saturday are both S; the position in the row is what
        // tells them apart, which every paper diary has always relied on.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 4
          Repeater {
            model: root.app.weekOrder
            delegate: Rectangle {
              id: day
              required property int modelData
              readonly property bool on: root.draft ? root.draft.days.indexOf(modelData) >= 0 : false
              width: 40
              height: 40
              radius: root.app.ui.radius
              color: on ? root.app.ui.accent : dayTap.pressed ? root.app.ui.pressed : root.app.ui.surfaceHigh
              Accessible.role: Accessible.CheckBox
              Accessible.name: Alarms.DAY_SHORT[modelData]
              Accessible.checked: on
              Text {
                anchors.centerIn: parent
                text: Alarms.DAY_INITIAL[day.modelData]
                color: day.on ? root.app.ui.inkOnAccent : root.app.ui.muted
                font.family: root.app.ui.font
                font.pixelSize: root.app.ui.fs.sm
                font.weight: Font.Bold
              }
              MouseArea {
                id: dayTap
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.app.toggleDay(day.modelData)
              }
            }
          }
        }
      }

      Card {
        app: root.app
        width: parent.width
        title: "Label"
        // Not bound to the draft: typing writes `text`, and a write breaks a
        // binding. Pushed in once, when the page is made.
        TextField {
          id: label
          app: root.app
          width: parent.width
          placeholder: "Work, pills, the bread"
          onTextChanged: if (root.draft && text !== root.draft.label) root.app.change("label", text)
          onAccepted: root.app.saveDraft()
          Component.onCompleted: text = root.draft ? root.draft.label : ""
        }
      }
    }
  }
}
