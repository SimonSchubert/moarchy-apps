import * as Api from "Api.mjs"

// The expensive half of every answer, off the UI thread: JSON.parse of a few
// hundred kilobytes (a plan carries every intermediate stop and the shape of
// every leg) and the copy into the few fields the app keeps. The request
// itself stays in Motis.qml; only text comes here, and only plain data goes
// back.
WorkerScript.onMessage = function (m) {
  if (m.op === "shape") {
    var data = null
    try { data = Api.shape(m.kind, JSON.parse(m.text)) } catch (e) { data = null }
    WorkerScript.sendMessage({ op: "shaped", url: m.url, kind: m.kind, data: data })
  } else if (m.op === "parse") {
    var entries = null
    try {
      var s = JSON.parse(m.text)
      if (s && s.version === 1 && s.entries) entries = s.entries
    } catch (e) { entries = null }
    WorkerScript.sendMessage({ op: "parsed", entries: entries })
  }
}
