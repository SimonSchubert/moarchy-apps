import QtQuick
import Quickshell.Io
import "Helper.js" as Helper

// One run of the helper at a time: a verb, the request as JSON on stdin, and
// the answer as the last line of stdout. Panel.qml keeps two of these, so a
// message being opened is not queued behind a folder taking its time.
Process {
  id: lane
  property var job: null
  signal answered(var job, var answer)
  running: false
  stdinEnabled: true
  stdout: StdioCollector { id: laneOut; waitForEnd: true }
  stderr: StdioCollector { id: laneErr; waitForEnd: true }
  // The request goes in and stdin is closed, which is the end of it.
  onStarted: {
    lane.write(JSON.stringify(lane.job.input))
    lane.stdinEnabled = false
  }
  // qmllint disable signal-handler-parameters
  onExited: function (code, status) {
    var done = lane.job
    lane.job = null
    lane.answered(done, Helper.result(code, laneOut.text, laneErr.text))
  }
  // qmllint enable signal-handler-parameters
}
