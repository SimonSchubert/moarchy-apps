"""Somebody else's JSON, our own file, and every figure on screen.

No GTK here, so this suite runs anywhere -- which is the point of keeping
`launches.py` and `store.py` free of it. Between them they hold everything in
this app that can be quietly wrong: a field Launch Library stopped sending, a
TBC drawn as a ticking clock, a favourites file half written by a phone that
was killed mid-tap.

Nothing in here touches the network. The one class that would is driven through
a stand-in for `urlopen`, because the failures worth testing -- a 429, a body
that is not JSON -- are exactly the ones a real request will not produce on
demand.
"""

from __future__ import annotations

import io
import json
import sys
import time
import unittest
import urllib.error
from datetime import datetime, timezone
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_launches import launches  # noqa: E402
from moarchy_launches.launches import Launch, LaunchError  # noqa: E402
from moarchy_launches.store import Store  # noqa: E402

FIXTURE = json.loads(
    (HERE / "tests" / "fixtures" / "upcoming.json").read_text(encoding="utf-8")
)

NOW = datetime(2026, 9, 14, 18, 0, 0, tzinfo=timezone.utc)

LIST_MODE = {
    "id": "electron-capella",
    "name": "Electron | Capella 17",
    "status": {"id": 8, "name": "To Be Confirmed", "abbrev": "TBC"},
    "net": "2026-09-16T18:00:00Z",
    "net_precision": {"abbrev": "MIN"},
    "lsp_name": "Rocket Lab",
    "mission": "Capella 17",
    "mission_type": "Earth Observation",
    "pad": "Launch Complex 1A",
    "location": "Mahia Peninsula, New Zealand",
    "orbit": "SSO",
    "type": "list",
}


def launch(
    identifier="vega-sentinel",
    name="Sentinel-3C & FLEX",
    vehicle="Vega-C",
    agency="Arianespace",
    status_id=launches.STATUS_GO,
    status="Go",
    net=None,
    precision="SEC",
    **extra,
) -> Launch:
    return Launch(
        id=identifier,
        name=name,
        vehicle=vehicle,
        agency=agency,
        status_id=status_id,
        status=status,
        net=net or datetime(2026, 9, 15, 1, 21, 7, tzinfo=timezone.utc),
        precision=precision,
        window_start=extra.get("window_start"),
        window_end=extra.get("window_end"),
        pad=extra.get("pad", "Ensemble de Lancement Vega"),
        location=extra.get("location", "Guiana Space Centre, French Guiana"),
        orbit=extra.get("orbit", "SSO"),
        mission_type=extra.get("mission_type", "Earth Science"),
        probability=extra.get("probability", 75),
        weather=extra.get("weather", ""),
        hold=extra.get("hold", ""),
        description=extra.get("description", ""),
    )


class TestParsing(unittest.TestCase):
    def test_a_normal_result_comes_through_whole(self):
        parsed = launches.parse(FIXTURE["results"][0])
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed.id, "vega-sentinel")
        self.assertEqual(parsed.name, "Sentinel-3C & FLEX")
        self.assertEqual(parsed.vehicle, "Vega-C")
        self.assertEqual(parsed.agency, "Arianespace")
        self.assertEqual(parsed.status_id, launches.STATUS_GO)
        self.assertEqual(parsed.orbit, "SSO")
        self.assertEqual(parsed.probability, 75)
        self.assertEqual(parsed.weather, "Cumulus Cloud Rule")
        self.assertEqual(parsed.pad, "Ensemble de Lancement Vega")

    def test_a_list_mode_row_still_parses(self):
        """Defensive: we request normal mode, but a cache might not."""
        parsed = launches.parse(LIST_MODE)
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed.agency, "Rocket Lab")
        self.assertEqual(parsed.name, "Capella 17")
        self.assertEqual(parsed.vehicle, "Electron")
        self.assertEqual(parsed.pad, "Launch Complex 1A")
        self.assertEqual(parsed.location, "Mahia Peninsula, New Zealand")

    def test_a_launch_with_no_net_is_not_a_row(self):
        record = {**FIXTURE["results"][0], "net": None}
        self.assertIsNone(launches.parse(record))

    def test_a_minus_one_probability_is_missing_rather_than_negative(self):
        parsed = launches.parse(FIXTURE["results"][1])
        self.assertIsNone(parsed.probability)

    def test_a_bool_is_not_a_number(self):
        record = {**FIXTURE["results"][0], "probability": True}
        parsed = launches.parse(record)
        self.assertIsNone(parsed.probability)

    def test_one_bad_row_does_not_take_the_list_with_it(self):
        payload = {
            "results": [FIXTURE["results"][0], {"id": "broken"}, FIXTURE["results"][1]]
        }
        found = launches.parse_upcoming(payload)
        self.assertEqual([item.id for item in found], ["vega-sentinel", "falcon-o3b"])

    def test_an_answer_that_is_not_a_list_is_an_error(self):
        with self.assertRaises(LaunchError):
            launches.parse_upcoming({"error": "nope"})

    def test_an_answer_where_nothing_is_usable_is_an_error(self):
        with self.assertRaises(LaunchError):
            launches.parse_upcoming({"results": [{"nope": 1}, {"nope": 2}]})

    def test_an_empty_list_is_not_an_error(self):
        self.assertEqual(launches.parse_upcoming({"results": []}), [])

    def test_a_fixture_round_trips_through_our_own_shape(self):
        parsed = launches.parse(FIXTURE["results"][0])
        again = Launch.from_dict(parsed.to_dict())
        self.assertEqual(again.id, parsed.id)
        self.assertEqual(again.net, parsed.net)
        self.assertEqual(again.probability, parsed.probability)


class TestCountdown(unittest.TestCase):
    def test_a_fine_net_ticks(self):
        item = launch(net=datetime(2026, 9, 14, 18, 12, 0, tzinfo=timezone.utc))
        self.assertEqual(launches.headline(item, now=NOW), "T-00:12:00")

    def test_a_net_more_than_a_day_away_drops_the_seconds(self):
        item = launch(net=datetime(2026, 9, 16, 22, 0, 0, tzinfo=timezone.utc))
        self.assertEqual(launches.headline(item, now=NOW), "T-2d 04h")

    def test_a_go_that_has_passed_counts_up(self):
        item = launch(net=datetime(2026, 9, 14, 17, 56, 48, tzinfo=timezone.utc))
        self.assertEqual(launches.headline(item, now=NOW), "T+00:03:12")

    def test_a_success_is_an_age_not_a_countdown(self):
        item = launch(
            status_id=launches.STATUS_SUCCESS,
            status="Success",
            net=datetime(2026, 9, 14, 4, 0, 0, tzinfo=timezone.utc),
        )
        self.assertEqual(launches.headline(item, now=NOW), "14 hours ago")

    def test_a_tbc_is_a_date_even_when_the_precision_is_a_minute(self):
        """A TBC that ticks seconds is a fake clock."""
        item = launch(
            status_id=launches.STATUS_TBC,
            status="TBC",
            precision="MIN",
            net=datetime(2026, 9, 16, 18, 0, 0, tzinfo=timezone.utc),
        )
        drawn = launches.headline(item, now=NOW)
        self.assertNotIn("T-", drawn)
        self.assertNotIn("T+", drawn)

    def test_a_quarter_does_not_tick(self):
        item = launch(
            precision="Q3",
            net=datetime(2026, 9, 16, 18, 0, 0, tzinfo=timezone.utc),
        )
        self.assertEqual(launches.headline(item, now=NOW), "Q3 2026")

    def test_frozen_now_is_deterministic(self):
        item = launch(net=datetime(2026, 9, 14, 18, 12, 0, tzinfo=timezone.utc))
        with mock.patch.dict(
            "os.environ", {"MOARCHY_LAUNCHES_NOW": "2026-09-14T18:00:00Z"}
        ):
            self.assertEqual(launches.headline(item), "T-00:12:00")
            self.assertEqual(launches.headline(item), "T-00:12:00")

    def test_a_go_in_the_next_hour_is_soon(self):
        item = launch(net=datetime(2026, 9, 14, 18, 12, 0, tzinfo=timezone.utc))
        self.assertEqual(launches.tone(item, now=NOW), "soon")

    def test_a_go_that_has_passed_is_late(self):
        item = launch(net=datetime(2026, 9, 14, 17, 50, 0, tzinfo=timezone.utc))
        self.assertEqual(launches.tone(item, now=NOW), "late")

    def test_a_tbc_is_wait(self):
        item = launch(status_id=launches.STATUS_TBC, status="TBC")
        self.assertEqual(launches.tone(item, now=NOW), "wait")


class TestRefresh(unittest.TestCase):
    def test_a_quiet_list_waits_fifteen_minutes(self):
        item = launch(net=datetime(2026, 9, 20, 0, 0, 0, tzinfo=timezone.utc))
        self.assertEqual(launches.refresh_after([item], now=NOW), launches.REFRESH_S)

    def test_a_go_in_the_next_hour_shortens_that(self):
        item = launch(net=datetime(2026, 9, 14, 18, 40, 0, tzinfo=timezone.utc))
        self.assertEqual(
            launches.refresh_after([item], now=NOW), launches.NEAR_REFRESH_S
        )

    def test_a_go_in_the_next_ten_minutes_shortens_it_again(self):
        item = launch(net=datetime(2026, 9, 14, 18, 8, 0, tzinfo=timezone.utc))
        self.assertEqual(
            launches.refresh_after([item], now=NOW), launches.IMMINENT_REFRESH_S
        )

    def test_a_success_does_not_hurry_the_clock(self):
        item = launch(
            status_id=launches.STATUS_SUCCESS,
            status="Success",
            net=datetime(2026, 9, 14, 18, 5, 0, tzinfo=timezone.utc),
        )
        self.assertEqual(launches.refresh_after([item], now=NOW), launches.REFRESH_S)


class TestSearching(unittest.TestCase):
    def test_a_query_matches_the_front_of_any_word(self):
        item = launch()
        self.assertTrue(item.matches("sen"))
        self.assertTrue(item.matches("vega"))
        self.assertTrue(item.matches("ariane"))
        self.assertFalse(item.matches("canaveral"))
        self.assertTrue(
            launch(location="Cape Canaveral SFS, FL, USA").matches("canaveral")
        )

    def test_a_query_does_not_match_the_middle_of_a_word(self):
        self.assertFalse(launch().matches("ega"))
        self.assertFalse(launch().matches("entin"))


class TestDisc(unittest.TestCase):
    def test_the_badge_is_short_enough_for_the_disc(self):
        self.assertEqual(launches.disc(launch()), "GO")
        self.assertEqual(
            launches.disc(
                launch(status_id=launches.STATUS_IN_FLIGHT, status="In Flight")
            ),
            "FLY",
        )
        self.assertLessEqual(
            len(launches.disc(launch(status_id=launches.STATUS_FAILURE))), 4
        )


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()
        return False


class TestLive(unittest.TestCase):
    def test_the_url_asks_for_twenty_and_does_not_paginate(self):
        url = launches.Live()._url()
        self.assertIn("limit=20", url)
        self.assertNotIn("offset", url)
        self.assertNotIn("mode=", url)

    def test_a_count_past_the_endpoints_ceiling_is_clamped(self):
        self.assertIn("limit=100", launches.Live(count=9999)._url())

    def _answer(self, payload):
        return mock.patch.object(
            launches.urllib.request,
            "urlopen",
            return_value=FakeResponse(json.dumps(payload).encode()),
        )

    def test_a_good_answer_becomes_launches(self):
        with self._answer(FIXTURE):
            found = launches.Live().upcoming()
        self.assertEqual([item.id for item in found], ["vega-sentinel", "falcon-o3b"])

    def test_a_token_is_sent_as_authorization(self):
        captured = {}

        def fake_urlopen(request, timeout=None):
            captured["authorization"] = request.get_header("Authorization")
            return FakeResponse(json.dumps(FIXTURE).encode())

        with mock.patch.object(
            launches.urllib.request, "urlopen", side_effect=fake_urlopen
        ):
            launches.Live(key="secret-token").upcoming()
        self.assertEqual(captured["authorization"], "Token secret-token")

    def test_a_rate_limit_says_so_and_says_when(self):
        error = urllib.error.HTTPError(
            "https://example",
            429,
            "Too Many Requests",
            {"Retry-After": "90"},
            io.BytesIO(b""),
        )
        self.addCleanup(error.close)
        with (
            mock.patch.object(launches.urllib.request, "urlopen", side_effect=error),
            self.assertRaises(LaunchError) as caught,
        ):
            launches.Live().upcoming()
        self.assertEqual(caught.exception.retry_after, 90.0)
        self.assertIn("rate-limit", str(caught.exception))

    def test_a_rate_limit_with_no_advice_still_says_when(self):
        error = urllib.error.HTTPError(
            "https://example", 429, "Too Many Requests", {}, io.BytesIO(b"")
        )
        self.addCleanup(error.close)
        with (
            mock.patch.object(launches.urllib.request, "urlopen", side_effect=error),
            self.assertRaises(LaunchError) as caught,
        ):
            launches.Live().upcoming()
        self.assertEqual(caught.exception.retry_after, launches.RATE_LIMIT_S)

    def test_a_body_that_is_not_json_is_a_sentence(self):
        with (
            mock.patch.object(
                launches.urllib.request,
                "urlopen",
                return_value=FakeResponse(b"<html>maintenance</html>"),
            ),
            self.assertRaises(LaunchError) as caught,
        ):
            launches.Live().upcoming()
        self.assertIn("JSON", str(caught.exception))

    def test_no_network_is_one_sentence_whichever_way_it_failed(self):
        for failure in (
            urllib.error.URLError("unreachable"),
            TimeoutError("slow"),
            ConnectionResetError("reset"),
        ):
            with (
                mock.patch.object(
                    launches.urllib.request, "urlopen", side_effect=failure
                ),
                self.assertRaises(LaunchError) as caught,
            ):
                launches.Live().upcoming()
            self.assertIn("No answer", str(caught.exception))

    def test_an_oversize_body_is_refused_unread(self):
        huge = FakeResponse(b"x" * (launches.MAX_BYTES + 2))
        with (
            mock.patch.object(launches.urllib.request, "urlopen", return_value=huge),
            self.assertRaises(LaunchError) as caught,
        ):
            launches.Live().upcoming()
        self.assertIn("more than this app will read", str(caught.exception))


class StoreCase(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def store(self):
        return Store(self.dir)


class TestFavourites(StoreCase):
    def test_a_star_survives_the_app_being_killed(self):
        store = self.store()
        self.assertTrue(store.toggle("vega-sentinel"))
        store.save_favourites()

        reopened = self.store()
        reopened.load()
        self.assertEqual(reopened.favourites, ["vega-sentinel"])
        self.assertTrue(reopened.is_favourite("vega-sentinel"))

    def test_toggling_twice_leaves_nothing_behind(self):
        store = self.store()
        store.toggle("vega-sentinel")
        self.assertFalse(store.toggle("vega-sentinel"))
        self.assertEqual(store.favourites, [])

    def test_the_starred_page_is_in_the_order_things_were_starred(self):
        store = self.store()
        store.replace(
            [launch("a"), launch("b"), launch("c")],
            fetched=time.time(),
        )
        for identifier in ("b", "a", "c"):
            store.toggle(identifier)
        self.assertEqual([item.id for item in store.starred()], ["b", "a", "c"])

    def test_a_star_with_no_launch_behind_it_is_not_drawn(self):
        store = self.store()
        store.toggle("missing")
        self.assertEqual(store.starred(), [])

    def test_a_duplicated_file_does_not_draw_a_launch_twice(self):
        (self.dir / "favourites.json").write_text(
            json.dumps({"favourites": ["vega-sentinel", "vega-sentinel", 7, ""]}),
            encoding="utf-8",
        )
        store = self.store()
        store.load()
        self.assertEqual(store.favourites, ["vega-sentinel"])

    def test_a_file_that_cannot_be_read_is_moved_aside_rather_than_overwritten(self):
        path = self.dir / "favourites.json"
        path.write_text("{not json", encoding="utf-8")
        store = self.store()
        store.load()
        self.assertEqual(store.favourites, [])
        self.assertFalse(path.exists())
        self.assertTrue(list(self.dir.glob("favourites.broken-*.json")))


class TestCache(StoreCase):
    def test_launches_survive_a_launch_with_no_signal(self):
        store = self.store()
        store.replace([launch()], fetched=1_000_000.0)
        store.save_upcoming()

        reopened = self.store()
        reopened.load()
        self.assertEqual([item.id for item in reopened.launches], ["vega-sentinel"])
        self.assertEqual(reopened.fetched, 1_000_000.0)

    def test_an_empty_answer_is_never_written_over_a_good_one(self):
        store = self.store()
        store.save_upcoming()
        self.assertFalse((self.dir / "upcoming.json").exists())

    def test_a_duplicate_id_keeps_the_later_record_and_the_first_place(self):
        store = self.store()
        first = launch("vega-sentinel", probability=10)
        second = launch("vega-sentinel", probability=90)
        store.replace([first, launch("other"), second], fetched=1.0)
        self.assertEqual(
            [item.id for item in store.launches], ["vega-sentinel", "other"]
        )
        self.assertEqual(store.launches[0].probability, 90)

    def test_launches_that_were_never_fetched_are_infinitely_old(self):
        self.assertEqual(self.store().age(), float("inf"))

    def test_a_clock_that_went_backwards_does_not_make_launches_from_the_future(self):
        store = self.store()
        store.fetched = 2_000.0
        self.assertEqual(store.age(now=1_000.0), 0.0)


if __name__ == "__main__":
    unittest.main()
