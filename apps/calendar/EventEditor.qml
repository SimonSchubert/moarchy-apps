pragma ComponentBehavior: Bound

import QtQuick
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Dates.js" as Dates
import "Events.js" as Events

// One event, in four boxes in the order the question is asked: what it is,
// when it is, how often, and what colour. A page over the month on a phone; a
// pane beside it on a desktop.
//
// Every control writes straight into the app's draft, so there is one answer
// to "what is being edited" and Save has nothing to collect but the two times,
// which are read when they are finished with rather than on every keystroke --
// "9" on its way to "930" is not a time anybody meant.
Item {
  id: root
  property var app
  // A pane beside the month, rather than a page over it: a close cross
  // instead of a back arrow.
  property bool pane: false

  readonly property var draft: app.draft

  Component.onCompleted: { app.editor = root; fill() }
  Component.onDestruction: if (app.editor === root) app.editor = null

  // The fields from the draft, when a different event is opened.
  property string shownId: ""
  onDraftChanged: if (draft && draft.id !== shownId) fill()
  function fill() {
    if (!draft) return
    shownId = draft.id
    titleField.text = draft.title
    whereField.text = draft.where
    startField.text = Dates.formatTime(draft.start)
    endField.text = Dates.formatTime(draft.end)
  }

  function focusTitle() { titleField.takeFocus() }

  // Moving the start moves the end with it, keeping the length -- which is
  // what every calendar does and what nobody has ever had to be told. The
  // end is only ever pinned by typing into the end field.
  function commitStart() {
    if (!draft) return true
    var at = Dates.parseTime(startField.text)
    if (at < 0) {
      app.toast("\"" + startField.text + "\" is not a time")
      startField.text = Dates.formatTime(draft.start)
      return false
    }
    var length = Math.max(0, draft.end - draft.start)
    var d = Events.copy(draft)
    d.start = at
    d.end = Math.min(at + length, Dates.MINUTES - 1)
    app.draft = d
    startField.text = Dates.formatTime(d.start)
    endField.text = Dates.formatTime(d.end)
    return true
  }

  function commitEnd() {
    if (!draft) return true
    var at = Dates.parseTime(endField.text)
    if (at < 0) {
      app.toast("\"" + endField.text + "\" is not a time")
      endField.text = Dates.formatTime(draft.end)
      return false
    }
    if (at < draft.start) app.toast("An event cannot end before it starts")
    app.change("end", Math.max(at, draft.start))
    endField.text = Dates.formatTime(app.draft.end)
    return true
  }

  // Both times, whether or not Enter was ever pressed in them: a time typed
  // and then saved with the button is a time somebody meant.
  function commitTimes() {
    if (draft && draft.allDay) return
    commitStart()
    commitEnd()
  }

  // A time is read when its field is left, as well as on Enter.
  Connections {
    target: startField.input
    function onActiveFocusChanged() { if (!startField.input.activeFocus) root.commitStart() }
  }
  Connections {
    target: endField.input
    function onActiveFocusChanged() { if (!endField.input.activeFocus) root.commitEnd() }
  }

  // --- the bar ----------------------------------------------------------------

  Item {
    id: bar
    width: parent.width
    height: root.app.compact ? 60 : 64

    IconButton {
      id: backButton
      x: 4
      anchors.verticalCenter: parent.verticalCenter
      app: root.app
      glyph: root.pane ? KG.close : KG.back
      label: root.pane ? "Close" : "Back"
      onClicked: root.app.closeEditor()
    }
    Text {
      anchors.left: backButton.right
      anchors.leftMargin: 4
      anchors.right: actions.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.app.draftIsNew ? "New event" : "Event"
      color: root.app.ui.text
      font.family: root.app.ui.font
      font.pixelSize: root.app.compact ? 20 : 20
      font.weight: Font.Bold
      elide: Text.ElideRight
    }
    Row {
      id: actions
      anchors.right: parent.right
      anchors.rightMargin: root.app.compact ? 8 : 16
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6
      IconButton {
        visible: !root.app.draftIsNew
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        glyph: G.remove
        label: "Delete this event"
        onClicked: root.app.deleteDraft()
      }
      Button {
        anchors.verticalCenter: parent.verticalCenter
        app: root.app
        primary: true
        glyph: G.save
        text: "Save"
        onClicked: root.app.commitDraft()
      }
    }
  }

  // --- the form ---------------------------------------------------------------

  Flickable {
    id: flick
    anchors.top: bar.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: form.implicitHeight + 32
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: form
      x: root.app.ui.gutter
      y: 4
      width: flick.width - root.app.ui.gutter * 2
      spacing: 14

      Card {
        app: root.app
        width: parent.width
        title: "What"

        TextField {
          id: titleField
          app: root.app
          width: parent.width
          placeholder: "What is it?"
          inputHints: Qt.ImhNone
          onTextChanged: root.app.change("title", titleField.text)
          onAccepted: whereField.takeFocus()
        }
        TextField {
          id: whereField
          app: root.app
          width: parent.width
          placeholder: "Where"
          onTextChanged: root.app.change("where", whereField.text)
          onAccepted: root.app.resetFocus()
        }
      }

      Card {
        app: root.app
        width: parent.width
        title: "When"

        // The date, and the same grid as the month screen behind it.
        Rectangle {
          width: parent.width
          height: root.app.ui.target + 4
          radius: root.app.ui.radius
          color: root.app.pickingDate ? root.app.ui.selected : root.app.ui.well
          Icon {
            id: dateGlyph
            app: root.app
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            text: G.month
            size: 17
            color: root.app.pickingDate ? root.app.ui.accent : root.app.ui.muted
          }
          Text {
            anchors.left: dateGlyph.right
            anchors.leftMargin: 4
            anchors.right: chevron.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.draft ? Dates.fullDayLabel(root.draft.date) : ""
            color: root.app.ui.text
            font.family: root.app.ui.font
            font.pixelSize: root.app.ui.fs.md
            elide: Text.ElideRight
          }
          Icon {
            id: chevron
            app: root.app
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: KG.chevronDown
            size: 16
            rotation: root.app.pickingDate ? 180 : 0
            color: root.app.ui.muted
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.draft) root.app.editorMonth = Dates.monthOfDay(root.draft.date)
              root.app.pickingDate = !root.app.pickingDate
            }
          }
        }

        Column {
          visible: root.app.pickingDate
          width: parent.width
          spacing: 2
          Item {
            width: parent.width
            height: root.app.ui.target
            IconButton {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              app: root.app
              glyph: G.previous
              label: "The month before"
              onClicked: root.app.editorMonth -= 1
            }
            Text {
              anchors.centerIn: parent
              text: Dates.monthLabel(Dates.yearOf(root.app.editorMonth), Dates.monthOf(root.app.editorMonth))
              color: root.app.ui.text
              font.family: root.app.ui.font
              font.pixelSize: root.app.ui.fs.md
              font.weight: Font.DemiBold
            }
            IconButton {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              app: root.app
              glyph: G.next
              label: "The month after"
              onClicked: root.app.editorMonth += 1
            }
          }
          Month {
            app: root.app
            width: parent.width
            height: 20 + Dates.ROWS * 36
            compact: true
            year: Dates.yearOf(root.app.editorMonth)
            month: Dates.monthOf(root.app.editorMonth)
            weekStart: root.app.weekStart
            today: root.app.today
            selected: root.draft ? root.draft.date : ""
            onPicked: function (iso) { root.app.setDate(iso) }
          }
        }

        Toggle {
          app: root.app
          width: parent.width
          text: "All day"
          checked: root.draft ? root.draft.allDay : false
          onToggled: function (on) { root.app.change("allDay", on) }
        }

        Row {
          visible: !!root.draft && !root.draft.allDay
          width: parent.width
          spacing: 8
          TextField {
            id: startField
            app: root.app
            width: (parent.width - 8) / 2
            label: "Starts"
            placeholder: "09:30"
            inputHints: Qt.ImhPreferNumbers
            onAccepted: { root.commitStart(); endField.takeFocus() }
          }
          TextField {
            id: endField
            app: root.app
            width: (parent.width - 8) / 2
            label: "Ends"
            placeholder: "10:30"
            inputHints: Qt.ImhPreferNumbers
            onAccepted: { root.commitEnd(); root.app.resetFocus() }
          }
        }

        // How long it is, worked out rather than asked for. It is also the
        // only sign that "930" was understood as half past nine.
        Text {
          width: parent.width
          visible: !!root.draft && !root.draft.allDay && text.length > 0
          text: root.draft ? Dates.formatLength(root.draft.end - root.draft.start) : ""
          color: root.app.ui.muted
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
            model: Events.REPEATS
            delegate: Chip {
              id: chip
              required property var modelData
              app: root.app
              text: chip.modelData.label
              selected: !!root.draft && root.draft.repeat === chip.modelData.key
              onClicked: root.app.change("repeat", chip.modelData.key)
            }
          }
        }
        Text {
          width: parent.width
          visible: text.length > 0
          text: root.draft ? Events.describeRepeat(root.draft) : ""
          color: root.app.ui.muted
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          wrapMode: Text.Wrap
        }
      }

      Card {
        app: root.app
        width: parent.width
        title: "Colour"

        Flow {
          width: parent.width
          spacing: 10
          Repeater {
            model: Events.COLOURS
            delegate: Rectangle {
              id: swatch
              required property string modelData
              readonly property bool on: !!root.draft && root.draft.colour === swatch.modelData
              width: 32
              height: 32
              radius: 16
              color: root.app.eventColour(swatch.modelData)
              border.width: swatch.on ? 3 : 0
              border.color: root.app.ui.text
              Accessible.role: Accessible.RadioButton
              Accessible.name: swatch.modelData
              Accessible.checked: swatch.on
              Icon {
                visible: swatch.on
                anchors.centerIn: parent
                app: root.app
                text: G.save
                size: 16
                color: root.app.inkOn(swatch.color)
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.app.change("colour", swatch.modelData)
              }
            }
          }
        }
      }
    }
  }
}
