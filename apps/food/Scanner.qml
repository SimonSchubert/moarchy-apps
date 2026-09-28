import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "Glyphs.js" as G
import "Facts.js" as F

// The viewfinder, or a reason there is no camera.
//
// The camera is libexec/moarchy-food-scan, a process of its own: GStreamer's
// v4l2src and zbar, printing one line a code (see the helper's header). It
// runs while `active` -- the scan page on screen, the window open, no lookup
// in flight -- and is ended the moment any of that stops being true, so a
// phone in a pocket has no sensor running. The preview is a JPEG the helper
// rewrites four times a second, reloaded here as it is announced.
//
// A code is only reported upwards once it is a product barcode (Facts.fromScan)
// and not the same one as a moment ago: zbar fires every frame the bars are in
// view, and without the debounce one packet would be looked up a dozen times.
Item {
  id: root
  property var app
  property bool active: false
  // What to show instead of the camera: a lookup in flight.
  property string busyTitle: ""
  property string busyText: ""
  signal scanned(string code)

  // How long the same code is ignored after it was last accepted.
  readonly property int debounceMs: 2500

  // The helper: beside the app in the tree, and in /usr/lib when packaged.
  readonly property string helper: Quickshell.env("MOARCHY_FOOD_SCANNER")
    || (root.app.appDir === "/usr/share/moarchy-food" ? "/usr/lib/moarchy-food/moarchy-food-scan"
                                                        : root.app.appDir + "/libexec/moarchy-food-scan")

  // "starting", "live" or "blank".
  property string phase: "starting"
  property string reason: ""
  property string frame: ""
  property string lastCode: ""
  property real lastAt: 0

  onActiveChanged: sync()
  Component.onCompleted: sync()

  function sync() {
    if (active && !proc.running) {
      phase = "starting"
      reason = ""
      frame = ""
      proc.running = true
    } else if (!active && proc.running) {
      proc.running = false
    }
  }

  function heard(line) {
    var event
    try { event = JSON.parse(line) } catch (e) { return }
    if (!event || typeof event !== "object") return
    if (event.event === "ready") { phase = "live"; return }
    if (event.event === "frame") {
      frame = "file://" + event.path + "?" + event.n
      return
    }
    if (event.event === "error") {
      phase = "blank"
      reason = String(event.reason || "The camera stopped.")
      return
    }
    if (event.event === "code") {
      var code = F.fromScan(event.kind, event.symbol)
      if (!code) return
      var now = Date.now()
      if (code === lastCode && now - lastAt < debounceMs) return
      lastCode = code
      lastAt = now
      scanned(code)
    }
  }

  Process {
    id: proc
    running: false
    command: ["python3", root.helper]
    // A pipe, so the helper also ends when this process goes away without
    // saying so.
    stdinEnabled: true
    stdout: SplitParser { onRead: function (line) { root.heard(line) } }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      if (root.active && root.phase !== "blank") {
        root.phase = "blank"
        root.reason = code === 0 ? "The camera stopped." : "The camera did not start."
      }
    }
    // qmllint enable signal-handler-parameters
  }

  // ------------------------------------------------------------ drawing

  Rectangle {
    id: glass
    anchors.fill: parent
    visible: root.busyTitle === "" && root.phase !== "blank"
    radius: root.app.compact ? 0 : root.app.ui.radius
    color: root.app.ui.well
    clip: true

    // The whole frame, not a crop of it: a sensor is landscape and a phone
    // is portrait, and a crop would show a strip of the bars rather than
    // where the packet is.
    Image {
      id: picture
      anchors.fill: parent
      source: root.frame
      fillMode: Image.PreserveAspectFit
      cache: false
      asynchronous: false
      visible: root.frame !== ""
    }

    // The reticle: where the bars go, inside the frame when there is one.
    Rectangle {
      anchors.centerIn: parent
      width: Math.min((picture.visible && picture.paintedWidth > 0 ? picture.paintedWidth : parent.width) * 0.78, 360)
      height: Math.min(width * 0.46, (picture.visible && picture.paintedHeight > 0 ? picture.paintedHeight : parent.height) * 0.7)
      radius: root.app.ui.radius
      color: "transparent"
      border.width: 3
      border.color: root.app.ui.accent
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 24
      width: hint.implicitWidth + 32
      height: 36
      radius: root.app.ui.round(height)
      color: root.app.ui.alpha(root.app.ui.bg, 0.85)
      Row {
        id: hint
        anchors.centerIn: parent
        spacing: 6
        Spinner { visible: root.phase === "starting"; running: visible; app: root.app; size: 16; anchors.verticalCenter: parent.verticalCenter }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.phase === "starting" ? "Starting the camera" : "Point at a barcode"
          color: root.app.ui.text
          font.family: root.app.ui.font
          font.pixelSize: root.app.ui.fs.sm
          font.weight: Font.Bold
        }
      }
    }
  }

  EmptyState {
    anchors.centerIn: parent
    visible: !glass.visible
    app: root.app
    busy: root.busyTitle !== ""
    glyph: G.cameraOff
    title: root.busyTitle !== "" ? root.busyTitle : "Camera required"
    text: root.busyTitle !== "" ? root.busyText
      : root.reason + " Point this phone at a barcode to look up nutrition facts. There is no other way in."
  }
}
