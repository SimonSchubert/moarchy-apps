import QtQuick
import Quickshell.Io

// Requests in flight: one curl each, as many at once as the screens want,
// each answered to the function that asked. A screen that has moved on by the
// time its answer comes checks its own key and drops it; nothing here knows
// what a request was for.
//
// Offline (MOARCHY_VIDEO_LIBRARY_OFFLINE) no process is started: a request is
// answered from `fixture`, the answers dev/demo.py saved under the same key,
// or as a failure.
Item {
  id: root

  property bool offline: false
  property var fixture: ({})
  readonly property int busy: jobs.length
  property var jobs: []

  // done(exitCode, output), as curl would have ended.
  function run(key, argv, done) {
    if (offline) {
      var saved = fixture[key]
      Qt.callLater(function () {
        if (saved === undefined) done(7, "")
        else done(0, JSON.stringify(saved) + "\n200")
      })
      return
    }
    var job = runner.createObject(root, { key: key, command: argv })
    job.done = done
    jobs = jobs.concat([job])
    job.running = true
  }

  function finished(job, code, output) {
    jobs = jobs.filter(function (j) { return j !== job })
    var done = job.done
    job.destroy()
    if (typeof done === "function") done(code, output)
  }

  Component {
    id: runner
    Process {
      id: proc
      property string key: ""
      property var done: null
      stdout: StdioCollector { id: out; waitForEnd: true }
      // qmllint disable signal-handler-parameters
      onExited: function (code, status) { root.finished(proc, code, out.text) }
      // qmllint enable signal-handler-parameters
    }
  }
}
