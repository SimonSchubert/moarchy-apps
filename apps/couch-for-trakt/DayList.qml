import QtQuick
import "Glyphs.js" as G

// A list of dated rows under day headings that stay put while their day
// scrolls under them. Rows are { key, at, day, media, episode }.
ListView {
  id: list
  property var app
  property var rows: []
  property bool loading: false
  property string error: ""
  property bool more: false
  property string emptyGlyph: ""
  property string emptyTitle: ""
  property string emptyDetail: ""
  property string emptyAction: ""
  property Component topContent: null
  // function (row) -> the short text left of the poster, and right of it.
  property var leadFor: null
  property var noteFor: null
  property bool dimPast: false
  signal endReached()
  signal emptyTriggered()

  property int cursor: -1
  property bool armed: false

  clip: true
  reuseItems: true
  cacheBuffer: 600
  boundsBehavior: Flickable.DragOverBounds

  function step(dx, dy) {
    if (!count) return false
    var d = dy || dx
    cursor = Math.max(0, Math.min(count - 1, (cursor < 0 ? -1 : cursor) + (cursor < 0 ? 1 : d)))
    positionViewAtIndex(cursor, ListView.Contain)
    return true
  }
  function activateCurrent() {
    if (cursor < 0 || cursor >= rows.length) return false
    app.openMedia(rows[cursor].media)
    return true
  }
  function picked() { return cursor >= 0 && cursor < rows.length ? rows[cursor].media : null }
  function toTop() { positionViewAtBeginning(); cursor = -1 }

  onRowsChanged: if (cursor >= rows.length) cursor = -1

  property bool touched: false
  onMovementStarted: touched = true
  onOriginYChanged: if (!touched) positionViewAtBeginning()
  onContentHeightChanged: if (!touched) positionViewAtBeginning()
  onContentYChanged: if (more && count > 0 && contentY + height > contentHeight + originY - 400) endReached()
  onVerticalOvershootChanged: if (dragging && verticalOvershoot < -72) armed = true
  onDraggingChanged: if (!dragging && armed) { armed = false; app.refresh(true) }

  readonly property string today: { var d = new Date(app.clock); return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2) }

  // Rows carry their day; the first of each day draws its heading. ListView
  // sections want a model with roles, and these rows are plain arrays.
  readonly property var marked: {
    var out = []
    for (var i = 0; i < rows.length; i++)
      out.push({ row: rows[i], first: i === 0 || rows[i - 1].day !== rows[i].day })
    return out
  }
  model: marked

  // The heading of the day at the top stays put while it scrolls under it.
  readonly property string topDay: {
    contentY; count
    var i = indexAt(width / 2, contentY + 42)
    return i >= 0 && i < rows.length ? rows[i].day : ""
  }

  component DayHeading: Rectangle {
    id: head
    property var app
    property string day: ""
    property string today: ""
    readonly property bool isToday: day === today
    height: 40
    color: app.ui.bg
    Row {
      x: 14
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8
      Rectangle {
        visible: head.isToday
        anchors.verticalCenter: parent.verticalCenter
        width: 8
        height: 8
        radius: 4
        color: head.app.ui.accent
      }
      Text {
        id: dayText
        anchors.verticalCenter: parent.verticalCenter
        text: head.app.dayLabel(head.day)
        color: head.isToday ? head.app.ui.accent : head.app.ui.text
        font.family: head.app.ui.font
        font.pixelSize: head.app.ui.fs.md
        font.weight: Font.Bold
      }
      Text {
        anchors.baseline: dayText.baseline
        text: head.app.dateLabel(head.day)
        color: head.app.ui.muted
        font.family: head.app.ui.font
        font.pixelSize: head.app.ui.fs.xs
      }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: head.app.ui.divider }
  }

  DayHeading {
    z: 5
    parent: list
    width: list.width
    app: list.app
    day: list.topDay
    today: list.today
    visible: list.count > 0 && list.topDay !== "" && list.contentY > list.originY + (list.headerItem ? list.headerItem.height : 0)
  }

  header: Column {
    width: list.width
    Item {
      width: parent.width
      height: list.armed || list.verticalOvershoot < -24 ? 28 : 0
      visible: height > 0
      Text {
        anchors.centerIn: parent
        text: list.armed ? "Release to refresh" : "Pull to refresh"
        color: list.app.ui.muted
        font.family: list.app.ui.font
        font.pixelSize: list.app.ui.fs.xs
      }
    }
    Loader {
      width: parent.width
      active: list.topContent !== null
      sourceComponent: list.topContent
    }
    Placeholder {
      width: parent.width
      visible: list.count === 0
      app: list.app
      busy: list.loading && !list.error
      glyph: list.error ? G.alert : list.emptyGlyph
      title: list.error ? list.error : list.loading ? "Loading…" : list.emptyTitle
      detail: list.error ? "Try again in a moment." : list.loading ? "" : list.emptyDetail
      action: list.error ? "Try again" : list.loading ? "" : list.emptyAction
      onTriggered: list.error ? list.app.refresh(true) : list.emptyTriggered()
    }
  }

  delegate: Column {
    id: cell
    required property var modelData
    required property int index
    width: list.width
    DayHeading {
      visible: cell.modelData.first
      width: parent.width
      app: list.app
      day: cell.modelData.row.day
      today: list.today
    }
    MediaRow {
      width: parent.width
      app: list.app
      media: cell.modelData.row.media
      episode: cell.modelData.row.episode
      lead: list.leadFor ? list.leadFor(cell.modelData.row) : ""
      note: list.noteFor ? list.noteFor(cell.modelData.row) : ""
      dim: list.dimPast && cell.modelData.row.day < list.today
      current: cell.index === list.cursor
      onActivated: list.app.openMedia(cell.modelData.row.media)
    }
  }

  footer: Item {
    width: list.width
    height: list.more && list.count > 0 ? 64 : 16
    Spinner { anchors.centerIn: parent; app: list.app; running: list.more && list.loading && list.count > 0 }
  }
}
