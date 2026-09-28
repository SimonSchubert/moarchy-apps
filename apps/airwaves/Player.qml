import QtQuick
import Quickshell
import Quickshell.Io
import "Api.mjs" as Api

// The one thing that makes sound: mpv, as a process of its own, told what to
// do over its JSON IPC socket.
//
// Not QtMultimedia, for three reasons. Neither Quickshell nor its Qt brings
// it, so it would be a second media stack to install. It does not surface the
// song a station sends (Icecast's StreamTitle), which is most of what a radio
// app shows. And a decoder in the shell's own process is one crash from
// taking the whole shell with it; mpv falling over is a message on screen.
//
// mpv starts on the first play, not before: an app that is only looked at
// costs no process. Inside the Omarchy shell it keeps playing after the
// window closes -- a radio -- and quits once it is stopped with the window
// closed. The standalone app ends it with the window (see shell.qml).
//
// It reads your own mpv configuration, so an audio device chosen there, or a
// script such as mpv-mpris for media keys and the lock screen, applies here
// too. What the app depends on is set on the command line, which wins.
Item {
  id: root
  property var app
  // MOARCHY_AIRWAVES_OFFLINE: a play is shown and never heard. No mpv, no
  // listen counted, nothing added to Recent -- a screenshot of the player
  // with nothing reaching the network or the speakers.
  property bool pretend: false

  property var station: null
  // "stopped", "connecting", "playing", "buffering", "failed"
  readonly property string status: {
    if (failure) return "failed"
    if (!wanted || !station) return "stopped"
    if (!loaded) return "connecting"
    return buffering ? "buffering" : "playing"
  }
  readonly property bool active: status === "connecting" || status === "playing" || status === "buffering"
  property string song: ""
  property string codec: ""
  property string failure: ""
  // True when there is no mpv to run.
  property bool missing: false

  property int volume: 80
  property bool muted: false

  // When the sleep timer stops the music, in ms since the epoch; 0 for never.
  property real sleepAt: 0

  property bool wanted: false
  property bool loaded: false
  property bool buffering: false
  property int retries: 0

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  property string socketPath: ""
  property bool started: false
  property var pending: []

  // ------------------------------------------------------------ controls

  function play(s) {
    if (!s || !Api.uuid(s.id) || !Api.webUrl(s.stream)) return
    var same = station && station.id === s.id
    station = s
    wanted = true
    loaded = false
    buffering = false
    failure = ""
    codec = ""
    if (!same) song = ""
    retries = 0
    retryTimer.stop()
    if (pretend) { loaded = true; return }
    load()
    app.api.click(s.id)
    app.store.pushRecent(s)
  }

  function stop() {
    wanted = false
    loaded = false
    buffering = false
    song = ""
    retryTimer.stop()
    cancelSleep()
    send(["stop"])
    Qt.callLater(root.settle)
  }

  // Play and stop, not play and pause: a paused live stream resumes minutes
  // behind the broadcast, which is not what anybody means on a radio.
  function toggle() {
    if (active) stop()
    else if (station) play(station)
  }

  function setVolume(v) {
    var n = Math.max(0, Math.min(100, Math.round(v)))
    if (n === volume && !muted) return
    volume = n
    if (muted && n > 0) setMuted(false)
    send(["set_property", "volume", n])
    saveVolume.restart()
  }

  function setMuted(m) {
    muted = m
    send(["set_property", "mute", m])
    saveVolume.restart()
  }

  function sleepIn(minutes) {
    if (minutes <= 0) { cancelSleep(); return }
    sleepAt = Date.now() + minutes * 60000
    sleepTimer.interval = minutes * 60000
    sleepTimer.restart()
  }

  function cancelSleep() {
    sleepAt = 0
    sleepTimer.stop()
  }

  // For the standalone app, whose process ends with its window.
  function shutdown() {
    wanted = false
    if (mpv.running) quit()
  }

  // Nothing playing and nobody looking: mpv goes. The next play starts it.
  function settle() {
    if (!wanted && !app.opened && mpv.running) quit()
  }

  // Our end of the socket closes first, once the quit is written: mpv
  // going away under an open socket is an error in the log.
  function quit() {
    send(["quit"])
    socket.connected = false
    killTimer.restart()
  }

  // ------------------------------------------------------------ mpv

  function load() {
    if (!station) return
    send(["loadfile", station.stream, "replace"])
  }

  function send(cmd) {
    if (!mpv.running) {
      // Only a play starts mpv; anything else has nothing to talk to.
      if (cmd[0] !== "loadfile") return
      pending = [cmd]
      launch()
      return
    }
    if (!socket.connected) {
      var p = pending.filter(function (c) { return c[0] !== cmd[0] || cmd[0] === "set_property" })
      p.push(cmd)
      pending = p
      return
    }
    socket.write(JSON.stringify({ command: cmd }) + "\n")
    socket.flush()
  }

  function launch() {
    var dir = runtimeDir || app.store.cacheDir
    socketPath = dir + "/airwaves-mpv-" + Date.now().toString(36) + ".sock"
    missing = false
    started = false
    mpv.command = [
      // mpv dies with this process, however it dies: a shell that crashed
      // or was restarted would otherwise leave music playing that nothing
      // knows about and nothing can stop.
      "setpriv", "--pdeathsig", "TERM", "--",
      "mpv",
      "--idle=yes",
      // Silent but for one line: the moment the socket is there to connect
      // to (see mpv's stdout below).
      "--no-input-terminal",
      "--msg-level=all=no,ipc=v",
      "--no-video",
      "--force-window=no",
      "--audio-display=no",
      // A station's address is somebody else's text. No youtube-dl for it,
      // and a stream may reach only the network, never a file on this disk.
      "--ytdl=no",
      "--demuxer-lavf-o=protocol_whitelist=[http,https,tls,tcp,crypto,httpproxy]",
      "--network-timeout=20",
      "--cache=yes",
      "--audio-client-name=Airwaves",
      "--title=Airwaves",
      "--volume=" + volume,
      "--mute=" + (muted ? "yes" : "no"),
      "--input-ipc-server=" + socketPath
    ]
    mpv.running = true
  }

  function observe() {
    var props = ["metadata", "paused-for-cache", "core-idle", "volume", "mute", "audio-codec-name"]
    for (var i = 0; i < props.length; i++)
      socket.write(JSON.stringify({ command: ["observe_property", i + 1, props[i]] }) + "\n")
    var p = pending
    pending = []
    for (var j = 0; j < p.length; j++) socket.write(JSON.stringify({ command: p[j] }) + "\n")
    socket.flush()
  }

  function handle(line) {
    var m = null
    try { m = JSON.parse(line) } catch (e) { return }
    if (!m || typeof m !== "object") return
    if (m.event === "property-change") {
      if (m.name === "metadata") {
        song = Api.song(m.data, station ? station.name : "")
      } else if (m.name === "paused-for-cache") {
        buffering = m.data === true
      } else if (m.name === "core-idle") {
        // Sound is coming out: the stream is up, even before file-loaded
        // on some HLS streams.
        if (m.data === false && wanted) loaded = true
      } else if (m.name === "volume" && typeof m.data === "number") {
        volume = Math.max(0, Math.min(100, Math.round(m.data)))
      } else if (m.name === "mute" && typeof m.data === "boolean") {
        muted = m.data
      } else if (m.name === "audio-codec-name") {
        codec = typeof m.data === "string" ? Api.clean(m.data, 16).toUpperCase() : ""
      }
    } else if (m.event === "file-loaded") {
      if (wanted) loaded = true
    } else if (m.event === "end-file") {
      if (!wanted) return
      // "stop" and "redirect" are ours or mpv's own: another station was
      // loaded over this one, or a playlist opened into its stream.
      if (m.reason === "error") fault(m.file_error)
      else if (m.reason === "eof") fault("eof")
    }
  }

  // A stream that dropped is tried again, twice, before it counts as gone:
  // mobile data does that.
  function fault(why) {
    loaded = false
    buffering = false
    if (retries < 2 && why !== "unrecognized file format" && why !== "no audio or video data played") {
      retries++
      retryTimer.restart()
      return
    }
    failure = why === "eof" ? "The station stopped sending."
      : why === "unrecognized file format" || why === "no audio or video data played" ? "This stream isn't audio Airwaves can play."
      : why === "loading failed" ? "Can't reach this station's stream."
      : "The station can't be played right now."
    wanted = false
  }

  function clearFailure() { failure = "" }

  function noPlayer() {
    missing = true
    wanted = false
    loaded = false
    failure = "Airwaves plays through mpv, which isn't installed."
  }

  Process {
    id: mpv
    onStarted: {
      root.started = true
      connectTimer.tries = 0
      connectTimer.interval = 2500
      connectTimer.restart()
    }
    // "[ipc] Listening to IPC socket." -- connecting before it is there is
    // an error in the log for every try.
    stdout: SplitParser {
      onRead: function (line) {
        if (line.indexOf("Listening to IPC socket") >= 0 && !socket.connected) socket.connected = true
      }
    }
    onRunningChanged: {
      if (running) return
      connectTimer.stop()
      killTimer.stop()
      socket.connected = false
      // It never started at all: there is no setpriv to run.
      if (!root.started) root.noPlayer()
      else if (root.wanted) {
        root.loaded = false
        root.wanted = false
        root.failure = "The player stopped unexpectedly."
      }
    }
    // 127 is setpriv finding no mpv to hand over to.
    // qmllint disable signal-handler-parameters
    onExited: function (exitCode, exitStatus) { if (exitCode === 127) root.noPlayer() }
  }

  Socket {
    id: socket
    path: root.socketPath
    parser: SplitParser {
      onRead: function (line) { root.handle(line) }
    }
    onConnectedChanged: if (connected) { connectTimer.stop(); root.observe() }
  }

  // Should mpv not say it is listening -- another version, other words --
  // knock until it answers, after a while.
  Timer {
    id: connectTimer
    property int tries: 0
    interval: 2500
    repeat: true
    onTriggered: {
      if (socket.connected || !mpv.running) { stop(); return }
      interval = 250
      if (++tries > 40) {
        stop()
        root.wanted = false
        root.failure = "The player didn't start."
        mpv.signal(15)
        return
      }
      socket.connected = true
    }
  }

  // A quit that was not heard: ended for it.
  Timer {
    id: killTimer
    interval: 1500
    onTriggered: if (mpv.running) mpv.signal(15)
  }

  Timer {
    id: retryTimer
    interval: 2500
    onTriggered: if (root.wanted) root.load()
  }

  Timer {
    id: sleepTimer
    onTriggered: { root.sleepAt = 0; root.stop(); root.app.toast("Sleep timer · stopped") }
  }

  Timer {
    id: saveVolume
    interval: 600
    onTriggered: { root.app.store.set("volume", root.volume); root.app.store.set("muted", root.muted) }
  }

  Connections {
    target: root.app
    function onOpenedChanged() { root.settle() }
  }
}
