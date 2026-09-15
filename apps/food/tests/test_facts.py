"""Somebody else's JSON, our own barcodes, and every number on screen.

No GTK here, so this suite runs anywhere -- which is the point of keeping
`facts.py` and `store.py` free of it. Nothing in here touches the network.
The one class that would is driven through a stand-in for `urlopen`.
"""

from __future__ import annotations

import io
import json
import struct
import sys
import unittest
import urllib.error
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_food import facts  # noqa: E402
from moarchy_food.camera import v4l2_is_capture  # noqa: E402
from moarchy_food.facts import FactsError, Live, Product  # noqa: E402
from moarchy_food.store import Store  # noqa: E402

NUTELLA = "3017620422003"

RECORD = {
    "status": 1,
    "code": NUTELLA,
    "product": {
        "code": NUTELLA,
        "product_name": "Nutella",
        "product_name_en": "Nutella",
        "brands": "Ferrero, Nutella",
        "quantity": "400 g",
        "nutriscore_grade": "e",
        "nova_group": 4,
        "ecoscore_grade": "d",
        "allergens_tags": ["en:milk", "en:nuts", "en:soybeans"],
        "ingredients_text_en": "Sugar, palm oil, hazelnuts.",
        "nutriments": {
            "energy-kcal_100g": 539,
            "fat_100g": 30.9,
            "saturated-fat_100g": 10.6,
            "carbohydrates_100g": 57.5,
            "sugars_100g": 56.3,
            "fiber_100g": 0,
            "proteins_100g": 6.3,
            "salt_100g": 0.107,
        },
        "image_front_small_url": "https://images.openfoodfacts.org/front.jpg",
        "additives_n": 2,
    },
}


class TestParsing(unittest.TestCase):
    def test_a_product_comes_through_whole(self):
        product = facts.parse(RECORD)
        self.assertEqual(product.code, NUTELLA)
        self.assertEqual(product.name, "Nutella")
        self.assertEqual(product.brand, "Ferrero")
        self.assertEqual(product.nutriscore, "e")
        self.assertEqual(product.nova, 4)
        self.assertEqual(product.allergens, ("Milk", "Nuts", "Soybeans"))
        self.assertEqual(len(product.nutrients), 8)
        self.assertEqual(product.nutrients[0].drawn(), "539 kcal")
        self.assertEqual(product.nutrients[1].drawn(), "30.9 g")

    def test_english_name_wins(self):
        payload = {
            "status": 1,
            "product": {
                "code": NUTELLA,
                "product_name": "Pâte à tartiner",
                "product_name_en": "Nutella",
            },
        }
        self.assertEqual(facts.parse(payload).name, "Nutella")

    def test_a_missing_product_is_missing_not_malformed(self):
        with self.assertRaises(FactsError) as raised:
            facts.parse(
                {"status": 0, "code": NUTELLA, "status_verbose": "product not found"}
            )
        self.assertTrue(raised.exception.missing)
        self.assertIn(NUTELLA, str(raised.exception))

    def test_a_product_with_no_name_is_not_a_page(self):
        with self.assertRaises(FactsError):
            facts.parse({"status": 1, "product": {"code": NUTELLA}})

    def test_unknown_grades_are_blank_not_a_letter(self):
        payload = {
            "status": 1,
            "product": {
                "code": NUTELLA,
                "product_name": "Water",
                "nutriscore_grade": "not-applicable",
                "ecoscore_grade": "unknown",
                "nova_group": 99,
            },
        }
        product = facts.parse(payload)
        self.assertEqual(product.nutriscore, "")
        self.assertEqual(product.ecoscore, "")
        self.assertIsNone(product.nova)

    def test_round_trip_through_our_own_file(self):
        original = facts.parse(RECORD)
        again = Product.from_dict(original.to_dict())
        self.assertEqual(again.code, original.code)
        self.assertEqual(again.allergens, original.allergens)
        self.assertEqual(again.nutrients[1].value, original.nutrients[1].value)


class TestBarcodes(unittest.TestCase):
    def test_nutella_is_an_ean13(self):
        self.assertEqual(facts.normalize_barcode(NUTELLA), NUTELLA)

    def test_a_upc_a_is_padded_to_ean13(self):
        # 036000291452 is a well-known UPC-A (check digit 2).
        self.assertEqual(facts.normalize_barcode("036000291452"), "0036000291452")

    def test_a_wrong_checksum_is_not_sent(self):
        self.assertIsNone(facts.normalize_barcode("3017620422004"))

    def test_letters_are_not_a_barcode(self):
        self.assertIsNone(facts.normalize_barcode("hello"))
        self.assertIsNone(facts.normalize_barcode(""))

    def test_an_ean13_scan_is_accepted(self):
        self.assertEqual(facts.from_scan("EAN-13", NUTELLA), NUTELLA)

    def test_a_qr_code_is_not_a_product(self):
        """A QR on a packet is a URL. This app has no browser in it."""
        self.assertIsNone(facts.from_scan("QR-Code", NUTELLA))
        self.assertIsNone(facts.from_scan("QRCode", "https://example.com"))

    def test_ean13_modules_are_ninety_five_bits(self):
        bits = facts.ean13_modules(NUTELLA)
        self.assertEqual(len(bits), 95)
        self.assertTrue(bits.startswith("101"))
        self.assertTrue(bits.endswith("101"))

    def test_a_png_of_the_code_is_a_real_png(self):
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "code.png"
            facts.write_ean13_png(path, NUTELLA)
            data = path.read_bytes()
            self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))
            self.assertGreater(len(data), 100)


class TestLive(unittest.TestCase):
    def test_a_product_url_names_the_barcode(self):
        live = Live()
        payload = json.dumps(RECORD).encode()

        def fake_urlopen(request, timeout=0):
            self.assertIn(NUTELLA, request.full_url)
            self.assertIn(
                "moarchy-food",
                request.get_header("User-agent")
                or request.get_header("User-Agent")
                or "",
            )
            return mock.MagicMock(
                __enter__=lambda s: s,
                __exit__=lambda *a: None,
                read=lambda n: payload,
            )

        with mock.patch("moarchy_food.facts.urllib.request.urlopen", fake_urlopen):
            product = live.product(NUTELLA)
        self.assertEqual(product.name, "Nutella")

    def test_a_429_is_ordinary(self):
        live = Live()
        error = urllib.error.HTTPError("https://x", 429, "rate", None, io.BytesIO())
        with (
            mock.patch("moarchy_food.facts.urllib.request.urlopen", side_effect=error),
            self.assertRaises(FactsError) as raised,
        ):
            live.product(NUTELLA)
        self.assertGreater(raised.exception.retry_after, 0)
        self.assertFalse(raised.exception.missing)

    def test_a_404_is_missing(self):
        live = Live()
        error = urllib.error.HTTPError("https://x", 404, "no", None, io.BytesIO())
        with (
            mock.patch("moarchy_food.facts.urllib.request.urlopen", side_effect=error),
            self.assertRaises(FactsError) as raised,
        ):
            live.product(NUTELLA)
        self.assertTrue(raised.exception.missing)


class TestStore(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.store = Store(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_scan_is_on_disk_before_the_page_opens(self):
        product = facts.parse(RECORD)
        self.store.remember(product)
        self.assertTrue(self.store.history_path.is_file())
        again = Store(self.tmp.name)
        again.load()
        self.assertEqual(again.history, [NUTELLA])
        self.assertEqual(again.get(NUTELLA).name, "Nutella")

    def test_scanning_the_same_packet_twice_moves_it_to_the_front(self):
        first = facts.parse(RECORD)
        second = Product.from_dict(
            {**first.to_dict(), "code": "5449000000996", "name": "Coca-Cola"}
        )
        self.store.remember(first)
        self.store.remember(second)
        self.store.remember(first)
        self.assertEqual(self.store.history, [NUTELLA, "5449000000996"])


def _querycap(caps: int, device_caps: int = 0) -> bytes:
    buf = bytearray(104)
    struct.pack_into("<II", buf, 84, caps, device_caps)
    return bytes(buf)


class TestCaptureNodes(unittest.TestCase):
    def test_a_csi_node_is_a_camera(self):
        # PinePhone /dev/video3: sun6i-csi-capture.
        self.assertTrue(v4l2_is_capture(_querycap(0x00000001)))

    def test_device_caps_win_when_the_card_advertises_them(self):
        # capabilities has the DEVICE_CAPS flag; the per-node bits are in
        # device_caps. A decoder that also lists capture in the union would
        # otherwise look like a camera.
        self.assertFalse(v4l2_is_capture(_querycap(0x80000001, device_caps=0x00000004)))
        self.assertTrue(v4l2_is_capture(_querycap(0x80000004, device_caps=0x00000001)))

    def test_a_rotator_is_not_a_camera(self):
        # PinePhone /dev/video0: sun8i-rotate. Opening it as v4l2src is how
        # a launch spent seconds in PLAYING on a node that will never frame.
        self.assertFalse(v4l2_is_capture(_querycap(0)))
        self.assertFalse(v4l2_is_capture(b""))
