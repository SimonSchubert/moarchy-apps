"""The camera, and the barcode it is pointed at.

A Linux phone's camera is a GStreamer pipeline. The decoder is zbar, the
same element `gst-plugins-bad` already ships, posting a message the moment
a code is in frame. There is no typed fallback: a barcode that cannot be
seen cannot be looked up, which is the whole of this module's job.

**The pipeline is not built until something asks it to start**, and it is
not built at all when there is nothing to point at. A headless check run
has no `/dev/video*`; constructing `v4l2src` anyway prints `ERROR` to
stderr, which `scripts/check.sh` treats as a failed run. Probing first is
what keeps a missing camera an empty state rather than a log line.

**A still is a camera, for one purpose.** `MOARCHY_FOOD_PREVIEW` points at
a PNG of a barcode and the pipeline is `filesrc ! pngdec ! imagefreeze`
instead of a device. That is how a screenshot of the scanner is a picture
of a barcode, and how the decoder is tested without a lens.
"""

from __future__ import annotations

import fcntl
import os
import struct
import time
from pathlib import Path

# Kinds zbar actually emits for a packet of food. The rest -- QR, DataBar,
# a boarding pass -- are not a product code and are ignored here rather
# than sent to Open Food Facts as a 404.
from .facts import from_scan

# How long the same code is ignored after it was last accepted. zbar fires
# every frame once the bars are in view; without this the app would look
# the same packet up twelve times a second.
DEBOUNCE_S = 2.5


def _gst():
    """GStreamer, or None if this machine does not have it.

    Imported on demand so a unit test that never starts the camera does not
    need the stack, and so a missing `gi.require_version` is not an import
    error for `window.py`.
    """
    try:
        import gi

        gi.require_version("Gst", "1.0")
        from gi.repository import Gst

        if not Gst.is_initialized():
            # Quiet: a missing plugin is a fallback, not a log the checks grep.
            os.environ.setdefault("GST_DEBUG", "0")
            Gst.init(None)
        return Gst
    except (ImportError, ValueError):
        return None


# struct v4l2_capability is 104 bytes on every LP64 we ship: driver[16],
# card[32], bus_info[32], version, capabilities, device_caps, reserved[3].
# VIDIOC_QUERYCAP is _IOR('V', 0, that struct).
_VIDIOC_QUERYCAP = 0x80685600
_V4L2_CAP_VIDEO_CAPTURE = 0x00000001
_V4L2_CAP_DEVICE_CAPS = 0x80000000


def v4l2_is_capture(buf: bytes) -> bool:
    """Does a QUERYCAP buffer advertise video capture?

    Pulled out so a test can hand it a buffer rather than a device. A PinePhone
    exposes four `/dev/video*` nodes and only one is a camera: the others are
    a rotator, a video decoder and a deinterlacer. Opening those as v4l2src
    is how a launch spends seconds in PLAYING on something that will never
    produce a frame.
    """
    if len(buf) < 92:
        return False
    caps, device_caps = struct.unpack_from("<II", buf, 84)
    flags = device_caps if caps & _V4L2_CAP_DEVICE_CAPS else caps
    return bool(flags & _V4L2_CAP_VIDEO_CAPTURE)


def _node_is_capture(path: Path) -> bool:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return False
    try:
        buf = bytearray(104)
        fcntl.ioctl(fd, _VIDIOC_QUERYCAP, buf)
    except OSError:
        return False
    finally:
        os.close(fd)
    return v4l2_is_capture(bytes(buf))


def devices() -> list[Path]:
    """Capture nodes that might be a camera.

    `/dev/video*` on this phone is mostly not a camera. Nodes that do not
    advertise `V4L2_CAP_VIDEO_CAPTURE` are skipped; an unreadable node is
    skipped because the app is not going to open it. If the ioctl is refused
    on every node, the whole list is returned rather than claiming there is
    no camera -- a container without V4L2 still has to be able to say so by
    having no nodes at all.
    """
    nodes = [
        path
        for path in sorted(Path("/dev").glob("video*"))
        if path.exists() and os.access(path, os.R_OK)
    ]
    capture = [path for path in nodes if _node_is_capture(path)]
    return capture or nodes


def preview_path() -> Path | None:
    raw = os.environ.get("MOARCHY_FOOD_PREVIEW", "")
    if not raw:
        return None
    path = Path(raw)
    return path if path.is_file() else None


def available() -> bool:
    """Is there something the pipeline can point at?

    A still counts. A `/dev/video*` that exists counts. PipeWire without a
    node does not: starting `pipewiresrc` with nothing at the other end is
    the ERROR line this function exists to avoid.
    """
    if os.environ.get("MOARCHY_FOOD_CAMERA") == "0":
        return False
    if preview_path() is not None:
        return True
    return bool(devices())


class Camera:
    """A viewfinder in a `Gtk.Picture`, and a callback for each new code.

    `start` / `stop` are idempotent. The window calls them from map/unmap
    and from the scan tab being selected, which on a phone is the difference
    between a camera that runs in a pocket and one that does not.
    """

    def __init__(self, picture) -> None:
        self._picture = picture
        self._on_code = None
        self._pipeline = None
        self._bus = None
        self._sink = None
        self._last = ""
        self._last_at = 0.0
        self._running = False
        self.reason = ""

    def on_code(self, callback) -> None:
        self._on_code = callback

    @property
    def running(self) -> bool:
        return self._running

    def start(self) -> bool:
        if self._running:
            return True
        gst = _gst()
        if gst is None:
            self.reason = "GStreamer is not installed."
            return False
        pipeline = self._build(gst)
        if pipeline is None:
            return False
        bus = pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self._on_message)
        result = pipeline.set_state(gst.State.PLAYING)
        if result == gst.StateChangeReturn.FAILURE:
            bus.remove_signal_watch()
            pipeline.set_state(gst.State.NULL)
            self.reason = "The camera did not start."
            return False
        self._pipeline = pipeline
        self._bus = bus
        self._running = True
        self.reason = ""
        return True

    def stop(self) -> None:
        gst = _gst()
        if self._bus is not None:
            self._bus.remove_signal_watch()
            self._bus = None
        if self._pipeline is not None and gst is not None:
            self._pipeline.set_state(gst.State.NULL)
            self._pipeline = None
        self._sink = None
        self._running = False
        if self._picture is not None:
            self._picture.set_paintable(None)

    def _build(self, gst):
        still = preview_path()
        if still is not None:
            location = str(still).replace("\\", "\\\\").replace('"', '\\"')
            source = f'filesrc location="{location}" ! pngdec ! imagefreeze'
            return self._launch(gst, source)
        for device in devices():
            source = f"v4l2src device={device}"
            pipeline = self._launch(gst, source)
            if pipeline is not None:
                return pipeline
        self.reason = "No camera found."
        return None

    def _launch(self, gst, source: str):
        """Preview + zbar, or None if this source cannot be built.

        gtk4paintablesink is the cheap preview: the widget holds a
        GdkPaintable the sink paints into, no CPU round-trip. If that
        plugin is missing, the pipeline is refused rather than falling
        through to a software copy -- a phone that can open a camera can
        install `gst-plugin-gtk4`, and a silent black viewfinder is worse
        than saying the camera did not start.
        """
        if gst.ElementFactory.find("zbar") is None:
            self.reason = "The zbar plugin is not installed."
            return None
        if gst.ElementFactory.find("gtk4paintablesink") is None:
            self.reason = "The GTK 4 video sink is not installed."
            return None
        description = (
            f"{source} ! tee name=t "
            "t. ! queue leaky=downstream max-size-buffers=2 ! "
            "videoconvert ! gtk4paintablesink name=preview "
            "t. ! queue leaky=downstream max-size-buffers=2 ! "
            "videoconvert ! zbar ! fakesink"
        )
        from gi.repository import GLib

        try:
            pipeline = gst.parse_launch(description)
        except GLib.Error:
            self.reason = "The camera pipeline could not be built."
            return None
        sink = pipeline.get_by_name("preview")
        if sink is None:
            pipeline.set_state(gst.State.NULL)
            self.reason = "The camera pipeline could not be built."
            return None
        paintable = sink.get_property("paintable")
        if paintable is not None and self._picture is not None:
            self._picture.set_paintable(paintable)
        self._sink = sink
        return pipeline

    def _on_message(self, _bus, message) -> None:
        gst = _gst()
        if gst is None:
            return
        if message.type == gst.MessageType.ELEMENT:
            structure = message.get_structure()
            if structure is None or structure.get_name() != "barcode":
                return
            kind = structure.get_string("type") or ""
            symbol = structure.get_string("symbol") or ""
            code = from_scan(kind, symbol)
            if code is None:
                return
            now = time.monotonic()
            if code == self._last and (now - self._last_at) < DEBOUNCE_S:
                return
            self._last = code
            self._last_at = now
            if self._on_code is not None:
                self._on_code(code)
            return
        if message.type == gst.MessageType.ERROR:
            # A device that existed at probe time and failed once PLAYING is
            # the ordinary broken-camera case on this hardware. Stop cleanly
            # so the window can show the reason rather than a frozen frame.
            err, _debug = message.parse_error()
            self.reason = err.message if err is not None else "The camera stopped."
            self.stop()
