pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Dates.js" as Dates
import "Events.js" as Events
import "Store.js" as CalendarFile

// A calendar: the month, the day under it, and what is next -- in one file,
// with no daemon and no account behind it.
//
//     omarchy-shell shell toggle org.moarchy.calendar
//
// Two tabs and an editor. **The month** is a grid with the chosen day's
// events beside or under it, so tapping the 14th answers "what is on the
// 14th" without going anywhere. **The agenda** is the same events as one
// list from today forward. **The editor** is one event, reached by the plus
// or by tapping something that already exists: a page on a phone, the pane
// beside the month on a desktop, where the grid is big enough to name what
// is on each day.
//
// The date picker in the editor is the same Month.qml the first screen draws.
// A picker that does not look like the calendar it came from is two things to
// learn instead of one.
App {
  id: root

  appId: "org.moarchy.calendar"
  title: "Calendar"
  // "Sep 2026" on a phone, where the month's arrows share the header with it.
  heading: tab !== "month" ? ""
    : compact ? Dates.MONTHS_SHORT[Dates.monthOf(shownMonth) - 1] + " " + Dates.yearOf(shownMonth)
    : Dates.monthLabel(Dates.yearOf(shownMonth), Dates.monthOf(shownMonth))
  subtitle: tab === "agenda" && agenda.length ? "From " + Dates.shortDayLabel(today) : ""
  windowWidth: 1240
  windowHeight: 820

  store: Store {
    name: "moarchy-calendar"
    defaults: ({ lastTab: "month", weekStart: -1 })
    clean: function (p) {
      if (["month", "agenda"].indexOf(p.lastTab) < 0) p.lastTab = "month"
      if ([-1, 0, 1, 6].indexOf(p.weekStart) < 0) p.weekStart = -1
      return p
    }
    onReadyChanged: if (ready && !root.pinnedTab) root.tab = prefs.lastTab
  }

  launcher.desktopId: "org.moarchy.Calendar"
  launcher.genericName: "Calendar"
  launcher.comment: "The month, the day under it, and what is next"
  launcher.categories: "Office;Calendar;"
  launcher.keywords: "calendar;events;agenda;appointment;schedule;month;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  // An event's colour is stored by name -- "green" -- and drawn in the
  // theme's green, so the same file under another theme is in that theme's
  // colours. Brown is nobody's terminal colour, so it is always this one.
  readonly property var eventPalette: ({
    blue: ui.hue("blue", "#60a5fa", "#2563eb"),
    green: ui.hue("green", "#4ade80", "#16a34a"),
    yellow: ui.hue("yellow", "#facc15", "#ca8a04"),
    orange: ui.hue("orange", "#fb923c", "#ea580c"),
    red: ui.hue("red", "#f87171", "#dc2626"),
    magenta: ui.hue("magenta", "#e879f9", "#c026d3"),
    cyan: ui.hue("cyan", "#22d3ee", "#0891b2"),
    brown: ui.dark ? "#c8a27a" : "#92643a"
  })

  function eventColour(name) { return eventPalette[name] || ui.accent }
  // A card washed in its event's colour: a pale tint on a light theme and a
  // dark one on a dark theme, rather than the same grey on both.
  function eventWash(name) { return Qt.tint(ui.bg, ui.alpha(eventColour(name), ui.dark ? 0.20 : 0.14)) }
  function inkOn(c) {
    var x = Qt.color(c)
    return 0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b > 0.6 ? "#111111" : "#ffffff"
  }

  tabs: [
    { key: "month", label: "Month", glyph: G.month },
    { key: "agenda", label: "Agenda", glyph: G.agenda }
  ]
  property bool pinnedTab: false
  onTabSelected: function (key) {
    if (key === "month" || key === "agenda") store.set("lastTab", key)
  }

  actions: Component {
    Row {
      spacing: 2
      Button {
        visible: root.tab === "month" && root.shownMonth !== Dates.monthOfDay(root.today)
        anchors.verticalCenter: parent.verticalCenter
        app: root
        text: "Today"
        onClicked: root.goToday()
      }
      IconButton {
        visible: root.tab === "month"
        app: root
        glyph: G.previous
        label: "The month before"
        onClicked: root.stepMonth(-1)
      }
      IconButton {
        visible: root.tab === "month"
        app: root
        glyph: G.next
        label: "The month after"
        onClicked: root.stepMonth(1)
      }
      IconButton {
        visible: root.compact
        app: root
        glyph: KG.plus
        label: "A new event"
        onClicked: root.startNew()
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "The month, the day under it, and what is next. One file, no accounts."
      SettingsSection {
        app: root
        width: parent.width
        title: "The week starts on"
        note: "The phone's own setting unless you pick a day."
        Flow {
          width: parent.width
          spacing: 8
          Repeater {
            model: [{ k: -1, l: "The system's" }, { k: 1, l: "Monday" }, { k: 0, l: "Sunday" }, { k: 6, l: "Saturday" }]
            delegate: Chip {
              required property var modelData
              app: root
              text: modelData.l
              selected: root.store.prefs.weekStart === modelData.k
              onClicked: root.store.set("weekStart", modelData.k)
            }
          }
        }
      }
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["1  2", "Month, Agenda"],
          ["← → ↑ ↓", "The day before, after, a week back, a week on"],
          ["PgUp PgDn", "The month before, after"],
          ["t", "Today"],
          ["n", "A new event on the chosen day"],
          ["Enter", "Open the chosen day's first event"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps the calendar"
        note: "~/.local/share/moarchy-calendar/calendar.json, in date order, with times as \"09:30\". A row this app cannot read is written back untouched. Nothing is synced and nothing leaves this computer."
      }
    }
  }

  // The editor on a phone: a page over the tab.
  page: Component { EventEditor { app: root } }

  // ------------------------------------------------------------ what is known

  property var events: []
  // Rows of the file this app could not read, written back untouched.
  property var strays: []
  property int revision: 0

  property string today: Dates.todayFrom(Date.now(), Quickshell.env("MOARCHY_CALENDAR_TODAY"))
  property string selected: today
  property int shownMonth: Dates.monthOfDay(today)

  // Which day the week starts on is the phone's business: Qt reads it off
  // the locale, Settings can pin it, and MOARCHY_CALENDAR_WEEK_START pins it
  // for the screenshots -- a container has no locales and would say Sunday.
  readonly property int weekStart: {
    var pinned = parseInt(Quickshell.env("MOARCHY_CALENDAR_WEEK_START") || "", 10)
    if (isFinite(pinned) && pinned >= 0 && pinned <= 6) return pinned
    var pref = store.prefs.weekStart
    if (pref >= 0 && pref <= 6) return pref
    var first = Qt.locale().firstDayOfWeek
    return (typeof first === "number" && first >= 0 && first <= 6) ? first : 1
  }

  readonly property var selectedEvents: {
    var r = revision
    return Events.onDay(events, selected)
  }
  readonly property var agenda: {
    var r = revision
    return opened ? Events.agenda(events, today, Events.HORIZON, Events.AGENDA_DAYS) : []
  }

  // ------------------------------------------------------------ moving about

  function selectDay(iso) {
    if (!Dates.isDay(iso)) return
    selected = iso
    shownMonth = Dates.monthOfDay(iso)
  }
  function goToday() {
    if (tab !== "month") setTab("month")
    selectDay(today)
  }
  function stepMonth(by) {
    var next = shownMonth + by
    selected = Dates.sameDayIn(next, selected)
    shownMonth = next
  }

  // ------------------------------------------------------------ the editor

  // The event being edited, or null. A copy, always: nothing in `events`
  // changes until Save, which is what makes Back a cancel.
  property var draft: null
  property bool draftIsNew: false
  property bool pickingDate: false
  property int editorMonth: 0
  // The editor on screen, which reads its two time fields on Save.
  property var editor: null

  function startNew() {
    var day = tab === "agenda" ? today : selected
    var at = day === today ? Dates.nextHalfHour(Date.now()) : -1
    openEditor(Events.blank(day, at, Events.nextColour(events), Date.now()), true)
    // The keyboard, at the field the event is named in: the one thing anybody
    // does first.
    Qt.callLater(function () { if (root.editor) root.editor.focusTitle() })
  }
  function startEdit(ev) { openEditor(Events.copy(ev), false) }

  function openEditor(ev, isNew) {
    draft = ev
    draftIsNew = !!isNew
    pickingDate = false
    editorMonth = Dates.monthOfDay(ev.date)
    if (compact && !topPage) push({ kind: "editor" })
  }

  function closeEditor() {
    draft = null
    pickingDate = false
    if (topPage) pop()
    resetFocus()
  }

  // Every control writes straight into the draft.
  function change(field, value) {
    if (!draft || draft[field] === value) return
    var d = Events.copy(draft)
    d[field] = value
    draft = d
  }
  function setDate(iso) {
    if (!Dates.isDay(iso)) return
    change("date", iso)
    pickingDate = false
  }

  function commitDraft() {
    if (!draft) return
    if (editor) editor.commitTimes()
    var title = String(draft.title || "").trim()
    if (!title.length) {
      toast("An event needs a name")
      if (editor) editor.focusTitle()
      return
    }
    var d = Events.copy(draft)
    d.title = title
    d.where = String(d.where || "").trim()
    events = Events.withEvent(events, d)
    revision += 1
    selectDay(d.date)
    closeEditor()
    save()
  }

  // Gone at once, and back with Undo for a few seconds: a file with one
  // version of itself has no other way to take it back.
  function deleteDraft() {
    if (!draft || draftIsNew) return
    var gone = Events.find(events, draft.id)
    events = Events.without(events, draft.id)
    revision += 1
    closeEditor()
    save()
    toast("Deleted " + (gone ? gone.title : "the event"), "Undo", function () {
      if (!gone) return
      root.events = Events.withEvent(root.events, gone)
      root.revision += 1
      root.save()
    })
  }

  // A page that was popped by Back took the draft with it.
  onTopPageChanged: if (!topPage && compact && draft) { draft = null; pickingDate = false }
  // Across the breakpoint the editor moves between page and pane.
  onCompactChanged: {
    if (!draft) return
    if (compact && !topPage) push({ kind: "editor" })
    else if (!compact && topPage) {
      var d = draft
      pop()
      draft = d
    }
  }

  // Before the tabs: the picker, then the desktop's editor pane.
  stepBack: function () {
    if (pickingDate) { pickingDate = false; return true }
    if (draft) { closeEditor(); return true }
    return false
  }

  keyHandler: function (event) {
    if (topPage || inSettings || draft) return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var k = event.key
    if (event.text === "n") { startNew(); event.accepted = true; return }
    if (event.text === "t") { goToday(); event.accepted = true; return }
    if (tab !== "month") return
    var step = k === Qt.Key_Left ? -1 : k === Qt.Key_Right ? 1 : k === Qt.Key_Up ? -7 : k === Qt.Key_Down ? 7 : 0
    if (step) { selectDay(Dates.addDays(selected, step)); event.accepted = true; return }
    if (k === Qt.Key_PageUp) { stepMonth(-1); event.accepted = true; return }
    if (k === Qt.Key_PageDown) { stepMonth(1); event.accepted = true; return }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && selectedEvents.length) {
      startEdit(selectedEvents[0])
      event.accepted = true
    }
  }

  onSummoned: function (payload) {
    if (payload && Dates.isDay(payload.day)) { setTab("month"); selectDay(payload.day) }
  }

  // ------------------------------------------------------------ the file

  function save() { file.save(CalendarFile.serialize(events, strays)) }

  DataFile {
    id: file
    app: "calendar"
    name: "calendar.json"
    // Re-read on every change, this app's own writes included: re-reading our
    // own save restores the state we were in, and re-reading somebody else's
    // -- a `jq` from a script, the file synced onto the phone -- puts it on
    // screen without a restart.
    onParsed: function (data) {
      var state = CalendarFile.parse(data)
      root.events = state.events
      root.strays = state.strays
      root.revision += 1
      if (!root.harnessed) { root.harnessed = true; Qt.callLater(root.applyLoadedHarness) }
    }
    onQuarantined: function (to) { root.toast("The calendar file was unreadable and was kept aside") }
  }

  // ------------------------------------------------------------ the harness

  property bool harnessed: false
  Component.onCompleted: {
    var day = Quickshell.env("MOARCHY_CALENDAR_DAY") || ""
    if (Dates.isDay(day)) selectDay(day)
    var page = Quickshell.env("MOARCHY_CALENDAR_PAGE") || ""
    if (page === "agenda" || page === "month") { tab = page; pinnedTab = true }
    if (page === "settings") { tab = "settings"; pinnedTab = true }
  }
  // After the file is in, and after the window has its width -- the editor
  // is a page or a pane depending on it.
  function applyLoadedHarness() { harnessTimer.start() }
  Timer {
    id: harnessTimer
    interval: 300
    onTriggered: {
      if ((Quickshell.env("MOARCHY_CALENDAR_NEW") || "") !== "") { root.startNew(); return }
      var want = Quickshell.env("MOARCHY_CALENDAR_EDIT") || ""
      if (!want) return
      var list = Events.onDay(root.events, root.selected)
      for (var i = 0; i < list.length; i++)
        if (list[i].title === want || list[i].id === want) {
          root.startEdit(list[i])
          if ((Quickshell.env("MOARCHY_CALENDAR_PICKING") || "") !== "") root.pickingDate = true
          return
        }
    }
  }

  // Midnight happens to a window that was left open. Checked once a minute,
  // and only while it is.
  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: {
      var now = Dates.todayFrom(Date.now(), Quickshell.env("MOARCHY_CALENDAR_TODAY"))
      if (now !== root.today) { root.today = now; root.revision += 1 }
    }
  }

  IpcHandler {
    target: "calendar"

    function today(): string { return root.today }

    // What is on a day, as the screen would say it. `on ""` is the day shown.
    function on(day: string): string {
      var iso = Dates.isDay(day) ? day : root.selected
      var list = Events.onDay(root.events, iso)
      var out = []
      for (var i = 0; i < list.length; i++) out.push(Events.summary(list[i]) + "  " + list[i].title)
      return out.length ? out.join("\n") : "nothing on " + Dates.fullDayLabel(iso)
    }

    function show(day: string): string {
      if (!Dates.isDay(day)) return "not a day: " + day
      root.setTab("month")
      root.selectDay(day)
      return root.selected
    }

    // One event, from a script: the reason a build that finishes at four can
    // put itself in somebody's calendar.
    function add(json: string): string {
      var raw
      try { raw = JSON.parse(String(json || "")) } catch (e) { return "not JSON: " + e }
      var ev = Events.normalise(raw, 0, Date.now())
      if (ev === null) return "an event needs a date, as \"date\": \"YYYY-MM-DD\""
      root.events = Events.withEvent(root.events, ev)
      root.revision += 1
      root.save()
      return ev.id
    }

    function remove(id: string): string {
      if (!Events.find(root.events, id)) return "no such event: " + id
      root.events = Events.without(root.events, String(id))
      root.revision += 1
      root.save()
      return "ok"
    }
  }

  // ------------------------------------------------------------ the screen

  // Everything left of the pane (all of it, on a phone).
  Item {
    id: mainArea
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: root.compact ? parent.right : pane.left

    // The month.
    Item {
      anchors.fill: parent
      visible: root.tab === "month"

      Month {
        id: grid
        app: root
        x: root.compact ? 4 : root.ui.gutter
        width: parent.width - x * 2
        height: root.compact ? 26 + Dates.ROWS * 52 : parent.height - 12
        large: !root.compact
        year: Dates.yearOf(root.shownMonth)
        month: Dates.monthOf(root.shownMonth)
        weekStart: root.weekStart
        today: root.today
        selected: root.selected
        // Nothing is walked for a window nobody can see: the shell keeps this
        // loaded from the moment it starts.
        events: root.opened ? root.events : []
        revision: root.revision
        onPicked: function (iso) { root.selectDay(iso) }
        onOpened: function (entry) { root.startEdit(entry) }

        // A swipe across the grid turns the month: the quick way, with the
        // arrows in the header as the certain one.
        DragHandler {
          id: swipe
          target: null
          xAxis.enabled: true
          yAxis.enabled: false
          onActiveChanged: {
            if (active) return
            var dx = swipe.centroid.position.x - swipe.centroid.pressPosition.x
            if (Math.abs(dx) > 60) root.stepMonth(dx < 0 ? 1 : -1)
          }
        }
      }

      DayList {
        visible: root.compact
        app: root
        anchors.top: grid.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
      }
    }

    AgendaList {
      anchors.fill: parent
      visible: root.tab === "agenda"
      app: root
    }
  }

  // On a desktop, the chosen day -- or the event being edited -- beside it.
  Rectangle {
    id: pane
    visible: !root.compact
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.rightMargin: root.ui.gutter
    anchors.bottomMargin: root.ui.gutter
    width: root.compact ? 0 : Math.min(400, Math.max(320, parent.width * 0.36))
    radius: root.ui.radius + 4
    color: root.ui.surface
    border.width: 1
    border.color: root.ui.divider

    Loader {
      anchors.fill: parent
      anchors.topMargin: 4
      active: !root.compact
      sourceComponent: root.draft ? editorPane : dayPane
    }
    Component { id: editorPane; EventEditor { app: root; pane: true } }
    Component { id: dayPane; DayList { app: root } }
  }
}
