import QtQuick
import Quickshell.Io

// Requests: one curl each, each answered to the function that asked. A
// screen that has moved on by the time its answer comes checks its own key
// and drops it; nothing here knows what a request was for.
//
// At most `parallel` at once, the rest queued in the order asked: Open
// Library is one volunteer-run server, and Discover alone would ask it for
// sixteen shelves in the same second. The same key asked twice while the
// first is waiting is asked once and answered twice.
//
// Offline (MOARCHY_BOOKS_OFFLINE) no process is started: a request is
// answered from `fixture`, the answers dev/capture.py saved under the same
// key, or as a failure.
Item {
  id: root

  property bool offline: false
  property var fixture: ({})
  property int parallel: 4
  readonly property int busy: jobs.length + queue.length
  property var jobs: []
  property var queue: []
  // key -> [done, ...] for a request asked again while it is out.
  property var waiting: ({})

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
    if (waiting[key]) { waiting[key].push(done); return }
    waiting[key] = [done]
    queue = queue.concat([{ key: key, argv: argv }])
    pump()
  }

  function pump() {
    while (jobs.length < parallel && queue.length) {
      var next = queue[0]
      queue = queue.slice(1)
      var job = runner.createObject(root, { key: next.key, command: next.argv })
      jobs = jobs.concat([job])
      job.running = true
    }
  }

  function finished(job, code, output) {
    jobs = jobs.filter(function (j) { return j !== job })
    var callbacks = waiting[job.key] || []
    delete waiting[job.key]
    job.destroy()
    for (var i = 0; i < callbacks.length; i++)
      if (typeof callbacks[i] === "function") callbacks[i](code, output)
    pump()
  }

  Component {
    id: runner
    Process {
      id: proc
      property string key: ""
      stdout: StdioCollector { id: out; waitForEnd: true }
      // qmllint disable signal-handler-parameters
      onExited: function (code, status) { root.finished(proc, code, out.text) }
      // qmllint enable signal-handler-parameters
    }
  }
}
