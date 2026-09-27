import * as Api from "Api.mjs"

// The expensive half of every answer, off the UI thread: JSON.parse of up to a
// few hundred kilobytes and the copy into the few fields the app keeps. A
// watchlist of a few hundred titles with full info took long enough on a phone
// to drop frames mid-scroll when it ran beside the grid. The request itself
// stays in Trakt.qml; only text comes here, and only plain data goes back.
WorkerScript.onMessage = function (m) {
  if (m.op === "shape") {
    var data = null
    try { data = Api.shape(m.kind, JSON.parse(m.text)) } catch (e) { data = null }
    WorkerScript.sendMessage({ op: "shaped", url: m.url, kind: m.kind, pages: m.pages, sentAt: m.sentAt, data: data })
  } else if (m.op === "parse") {
    var entries = null
    try {
      var s = JSON.parse(m.text)
      if (s && s.version === 1 && s.entries) entries = s.entries
    } catch (e) { entries = null }
    WorkerScript.sendMessage({ op: "parsed", entries: entries })
  }
}
