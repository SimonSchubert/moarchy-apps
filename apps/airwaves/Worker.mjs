import * as Api from "Api.mjs"

// The expensive half of every answer, off the UI thread: JSON.parse and the
// copy into the few fields the app keeps. The list of every country or tag is
// a few hundred kilobytes, and parsing it beside a scrolling list on a phone
// drops frames. The request itself stays in RadioBrowser.qml; only text comes
// here, and only plain data goes back.
WorkerScript.onMessage = function (m) {
  if (m.op === "shape") {
    var data = null
    try { data = Api.shape(m.kind, JSON.parse(m.text)) } catch (e) { data = null }
    WorkerScript.sendMessage({ op: "shaped", path: m.path, kind: m.kind, data: data })
  } else if (m.op === "parse") {
    var entries = null
    try {
      var s = JSON.parse(m.text)
      if (s && s.version === 1 && s.entries) entries = s.entries
    } catch (e) { entries = null }
    WorkerScript.sendMessage({ op: "parsed", entries: entries })
  }
}
