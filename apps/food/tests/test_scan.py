"""The scanning helper, without a lens.

What can be checked on any machine: which /dev/video* is a camera, what the
fake scanner replays, the pipeline line, and the protocol end to end through
the fake -- a process that says ready, prints the codes, and ends on SIGTERM
or on its stdin closing. The real pipeline is checked where GStreamer and zbar
are installed (MOARCHY_FOOD_GST=1), against a still of a barcode.

    python3 -m unittest discover -s apps/food/tests -p 'test_*.py'
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import signal
import struct
import subprocess
import sys
import time
import unittest
import zlib
from pathlib import Path
from tempfile import TemporaryDirectory

HELPER = Path(__file__).resolve().parent.parent / "libexec" / "moarchy-food-scan"
_loader = importlib.machinery.SourceFileLoader("food_scan", str(HELPER))
_spec = importlib.util.spec_from_loader("food_scan", _loader)
scan = importlib.util.module_from_spec(_spec)
_loader.exec_module(scan)

NUTELLA = "3017620422003"


def _querycap(caps: int, device_caps: int = 0) -> bytes:
    buf = bytearray(104)
    struct.pack_into("<II", buf, 84, caps, device_caps)
    return bytes(buf)


# EAN-13 as bars, for a still zbar can read -- what 0.1.0's facts.py drew.
_A = {
    "0": "0001101", "1": "0011001", "2": "0010011", "3": "0111101", "4": "0100011",
    "5": "0110001", "6": "0101111", "7": "0111011", "8": "0110111", "9": "0001011",
}
_B = {d: b[::-1].translate(str.maketrans("01", "10")) for d, b in _A.items()}
_C = {d: b.translate(str.maketrans("01", "10")) for d, b in _A.items()}
_P = {
    "0": "AAAAAA", "1": "AABABB", "2": "AABBAB", "3": "AABBBA", "4": "ABAABB",
    "5": "ABBAAB", "6": "ABBBAA", "7": "ABABAB", "8": "ABABBA", "9": "ABBABA",
}


def write_ean13_png(path: Path, code: str, scale: int = 3, quiet: int = 12, height: int = 80) -> None:
    left = "".join(_A[d] if p == "A" else _B[d] for d, p in zip(code[1:7], _P[code[0]], strict=True))
    bits = "101" + left + "01010" + "".join(_C[d] for d in code[7:]) + "101"
    width = (quiet * 2 + len(bits)) * scale
    white, black = b"\xff\xff\xff", b"\x00\x00\x00"
    row = (
        b"\x00"
        + white * quiet * scale
        + b"".join((black if b == "1" else white) * scale for b in bits)
        + white * quiet * scale
    )

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return struct.pack(">I", len(data)) + tag + data + crc

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(row * height, 9))
        + chunk(b"IEND", b"")
    )


def run(env: dict, seconds: float) -> tuple[list[dict], int]:
    """Start the helper, let it run, SIGTERM it: its events and exit code."""
    proc = subprocess.Popen(
        [sys.executable, str(HELPER)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        env={**os.environ, **env},
    )
    time.sleep(seconds)
    if proc.poll() is None:
        proc.send_signal(signal.SIGTERM)
    out, _ = proc.communicate(timeout=10)
    events = [json.loads(line) for line in out.decode().splitlines() if line.strip()]
    return events, proc.returncode


class TestCaptureNodes(unittest.TestCase):
    def test_a_csi_node_is_a_camera(self):
        # PinePhone /dev/video3: sun6i-csi-capture.
        self.assertTrue(scan.v4l2_is_capture(_querycap(0x00000001)))

    def test_device_caps_win_when_the_card_advertises_them(self):
        self.assertFalse(scan.v4l2_is_capture(_querycap(0x80000001, device_caps=0x00000004)))
        self.assertTrue(scan.v4l2_is_capture(_querycap(0x80000004, device_caps=0x00000001)))

    def test_a_rotator_is_not_a_camera(self):
        # PinePhone /dev/video0: sun8i-rotate.
        self.assertFalse(scan.v4l2_is_capture(_querycap(0)))
        self.assertFalse(scan.v4l2_is_capture(b""))

    def test_a_machine_with_no_nodes_has_no_camera(self):
        with TemporaryDirectory() as tmp:
            self.assertEqual(scan.devices(Path(tmp)), [])


class TestFake(unittest.TestCase):
    def test_lines_are_kind_and_symbol_or_just_digits(self):
        self.assertEqual(
            scan.fake_codes(f"# a comment\n\nEAN-8 96385074\n{NUTELLA}\n"),
            [("EAN-8", "96385074"), ("EAN-13", NUTELLA)],
        )

    def test_the_fake_says_ready_then_each_code_then_ends_on_sigterm(self):
        with TemporaryDirectory() as tmp:
            codes = Path(tmp) / "codes"
            codes.write_text(f"{NUTELLA}\nQR-Code https://example.com\n")
            env = {"MOARCHY_FOOD_SCAN_FAKE": str(codes), "MOARCHY_FOOD_SCAN_FAKE_DELAY": "0.1"}
            events, code = run(env, 1.0)
        self.assertEqual(code, 0)
        self.assertEqual(events[0], {"event": "ready"})
        self.assertEqual(events[1], {"event": "code", "kind": "EAN-13", "symbol": NUTELLA})
        # The helper reports; which kinds are products is the app's decision.
        self.assertEqual(events[2]["kind"], "QR-Code")

    def test_closing_stdin_ends_it(self):
        with TemporaryDirectory() as tmp:
            codes = Path(tmp) / "codes"
            codes.write_text(NUTELLA + "\n")
            proc = subprocess.Popen(
                [sys.executable, str(HELPER)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                env={**os.environ, "MOARCHY_FOOD_SCAN_FAKE": str(codes)},
            )
            proc.stdin.close()
            self.assertEqual(proc.wait(timeout=5), 0)
            proc.stdout.close()

    def test_a_bare_fixture_name_is_looked_for_in_the_data_dir(self):
        old = {k: os.environ.get(k) for k in ("MOARCHY_FOOD_DIR", "MOARCHY_FOOD_SCAN_FAKE")}
        try:
            os.environ["MOARCHY_FOOD_DIR"] = "/data/food"
            os.environ["MOARCHY_FOOD_SCAN_FAKE"] = "scan.txt"
            self.assertEqual(scan.fixture("MOARCHY_FOOD_SCAN_FAKE"), "/data/food/scan.txt")
            os.environ["MOARCHY_FOOD_SCAN_FAKE"] = "/elsewhere/scan.txt"
            self.assertEqual(scan.fixture("MOARCHY_FOOD_SCAN_FAKE"), "/elsewhere/scan.txt")
        finally:
            for k, v in old.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v

    def test_a_missing_fake_file_is_an_error_line(self):
        events, code = run({"MOARCHY_FOOD_SCAN_FAKE": "/nonexistent/codes"}, 0.5)
        self.assertEqual(events[0]["event"], "error")
        self.assertEqual(code, 2)


class TestCamera(unittest.TestCase):
    def test_no_camera_is_said_not_crashed(self):
        events, code = run({"MOARCHY_FOOD_CAMERA": "0"}, 0.5)
        self.assertEqual(events, [{"event": "error", "reason": "No camera found."}])
        self.assertEqual(code, 2)

    def test_the_pipeline_decodes_on_one_branch_and_previews_on_the_other(self):
        line = scan.describe("v4l2src device=/dev/video3", "/run/p.jpg")
        self.assertIn("zbar", line)
        self.assertIn("jpegenc", line)
        self.assertIn(f"framerate={scan.PREVIEW_FPS}/1", line)
        self.assertNotIn("jpegenc", scan.describe("v4l2src", None))

    @unittest.skipUnless(
        os.environ.get("MOARCHY_FOOD_GST") == "1",
        "needs GStreamer, gst-plugins-bad and zbar (MOARCHY_FOOD_GST=1)",
    )
    def test_the_real_pipeline_reads_a_still(self):
        with TemporaryDirectory() as tmp:
            still = Path(tmp) / "code.png"
            write_ean13_png(still, NUTELLA)
            events, code = run({"MOARCHY_FOOD_PREVIEW": str(still), "XDG_RUNTIME_DIR": tmp}, 4.0)
            frames = [e for e in events if e["event"] == "frame"]
            self.assertTrue(frames, events)
            self.assertTrue(Path(frames[-1]["path"]).read_bytes().startswith(b"\xff\xd8"))
        self.assertEqual(events[0], {"event": "ready"})
        self.assertIn({"event": "code", "kind": "EAN-13", "symbol": NUTELLA}, events)
        self.assertEqual(code, 0)


if __name__ == "__main__":
    unittest.main()
