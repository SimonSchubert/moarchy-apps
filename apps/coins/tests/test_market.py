"""Somebody else's JSON, our own file, and every number on screen.

No GTK here, so this suite runs anywhere -- which is the point of keeping
`market.py` and `store.py` free of it. Between them they hold everything in
this app that can be quietly wrong: a field CoinGecko stopped sending, a price
formatted into a row of zeroes, a favourites file half written by a phone that
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
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_coins import market  # noqa: E402
from moarchy_coins.market import Coin, MarketError  # noqa: E402
from moarchy_coins.store import Store  # noqa: E402

RECORD = {
    "id": "bitcoin",
    "symbol": "btc",
    "name": "Bitcoin",
    "current_price": 77243.0,
    "market_cap": 1_551_224_442_911,
    "market_cap_rank": 1,
    "price_change_percentage_24h": 0.16229,
}


def coin(identifier="bitcoin", rank=1, price=100.0, change=1.0, cap=1e9):
    return Coin(
        id=identifier,
        symbol=identifier[:3].upper(),
        name=identifier.title(),
        rank=rank,
        price=price,
        change=change,
        cap=cap,
    )


class TestParsing(unittest.TestCase):
    def test_a_coin_comes_through_whole(self):
        parsed = market.parse(RECORD, 1)
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed.id, "bitcoin")
        self.assertEqual(parsed.symbol, "BTC")
        self.assertEqual(parsed.rank, 1)
        self.assertAlmostEqual(parsed.price, 77243.0)

    def test_a_coin_with_no_price_is_not_a_row(self):
        """Every column on the right of the screen is derived from the price."""
        self.assertIsNone(market.parse({**RECORD, "current_price": None}, 1))
        self.assertIsNone(market.parse({**RECORD, "current_price": 0}, 1))

    def test_an_ordered_answer_is_numbered_by_where_the_coin_sat_in_it(self):
        """market_cap_rank disagrees with the ordering it arrives in."""
        parsed = market.parse({**RECORD, "market_cap_rank": 1}, 40)
        self.assertEqual(parsed.rank, 40)
        parsed = market.parse({**RECORD, "market_cap_rank": None}, 40)
        self.assertEqual(parsed.rank, 40)

    def test_a_rank_coingecko_repeats_is_not_drawn_twice(self):
        """The real answer of 2026-09-14: Figure Heloc and Zcash both came back
        as rank 9, correctly ordered by capitalisation, with Hyperliquid at 10.
        Drawn faithfully that is a list numbered 9, 9, 10."""
        answer = [
            {**RECORD, "id": "figure-heloc", "market_cap_rank": 9, "market_cap": 22e9},
            {**RECORD, "id": "zcash", "market_cap_rank": 9, "market_cap": 17e9},
            {**RECORD, "id": "hyperliquid", "market_cap_rank": 10, "market_cap": 17e9},
        ]
        self.assertEqual([c.rank for c in market.parse_markets(answer)], [1, 2, 3])

    def test_a_coin_fetched_by_name_keeps_the_rank_it_reports(self):
        """There the position means nothing: it arrived in a list of one."""
        coins = market.parse_markets(
            [{**RECORD, "id": "monero", "market_cap_rank": 187}], ordered=False
        )
        self.assertEqual(coins[0].rank, 187)

    def test_a_coin_nobody_has_ranked_sorts_to_the_end(self):
        coins = market.parse_markets(
            [{**RECORD, "id": "brand-new", "market_cap_rank": None}], ordered=False
        )
        self.assertEqual(coins[0].rank, market.UNRANKED)
        self.assertGreater(market.UNRANKED, market.TOP)

    def test_a_bool_is_not_a_number(self):
        """isinstance(True, int) is True in Python, and $1.00 is a lie."""
        self.assertIsNone(market.parse({**RECORD, "current_price": True}, 1))
        parsed = market.parse({**RECORD, "price_change_percentage_24h": True}, 1)
        self.assertIsNone(parsed.change)

    def test_a_missing_day_is_missing_rather_than_zero(self):
        parsed = market.parse({**RECORD, "price_change_percentage_24h": None}, 1)
        self.assertIsNone(parsed.change)
        self.assertEqual(market.percent(parsed.change), market.DASH)

    def test_one_bad_coin_does_not_take_the_list_with_it(self):
        coins = market.parse_markets([RECORD, {"id": "broken"}, RECORD])
        self.assertEqual(len(coins), 2)

    def test_an_answer_that_is_not_a_list_is_an_error(self):
        with self.assertRaises(MarketError):
            market.parse_markets({"error": "nope"})

    def test_an_answer_where_nothing_is_usable_is_an_error(self):
        """Not "a quiet market": the shape of the answer has changed."""
        with self.assertRaises(MarketError):
            market.parse_markets([{"nope": 1}, {"nope": 2}])

    def test_an_empty_market_is_not_an_error(self):
        self.assertEqual(market.parse_markets([]), [])


class TestPrices(unittest.TestCase):
    def test_a_big_price_drops_its_decimals(self):
        self.assertEqual(market.money(77243.0), "$77,243")

    def test_an_ordinary_price_keeps_two(self):
        self.assertEqual(market.money(2504.68), "$2,504.68")
        self.assertEqual(market.money(1.0), "$1.00")

    def test_a_price_in_five_figures_drops_them_too(self):
        """Nobody reads Bitcoin's cents, and they do not fit the column."""
        self.assertEqual(market.money(9999.99), "$9,999.99")
        self.assertEqual(market.money(10_000.4), "$10,000")

    def test_a_sub_cent_price_keeps_four_significant_figures(self):
        """A fixed two decimals draws every meme coin as $0.00."""
        self.assertEqual(market.money(0.0000119), "$0.00001190")
        # Four figures past the leading zeroes, trailing zero and all: the
        # column has to hold still while the price moves.
        self.assertEqual(market.money(0.00234), "$0.002340")

    def test_a_price_that_is_not_there_is_a_dash(self):
        self.assertEqual(market.money(None), market.DASH)
        self.assertEqual(market.money(0), market.DASH)

    def test_a_currency_without_a_sign_keeps_its_code(self):
        """Silently becoming dollars is the one wrong answer here."""
        self.assertEqual(market.money(12.5, "eur"), "€12.50")
        self.assertEqual(market.money(12.5, "sek"), "SEK 12.50")

    def test_a_market_cap_is_three_figures_and_a_letter(self):
        self.assertEqual(market.compact(1_551_224_442_911), "$1.55 T")
        self.assertEqual(market.compact(305_668_739_732), "$306 B")
        self.assertEqual(market.compact(12_400_000), "$12.4 M")
        self.assertEqual(market.compact(None), market.DASH)

    def test_a_day_is_always_signed(self):
        """The colour is the half a person sees first; the sign is the half
        that still works for somebody who cannot tell the two colours apart."""
        self.assertEqual(market.percent(0.16229), "+0.16%")
        self.assertEqual(market.percent(-0.5), "-0.50%")
        self.assertEqual(market.percent(0.0), "+0.00%")

    def test_a_day_that_rounds_to_nothing_is_drawn_as_nothing(self):
        """+0.00% in green is a claim the figure beside it does not make."""
        self.assertEqual(market.direction(0.001), "flat")
        self.assertEqual(market.direction(None), "flat")
        self.assertEqual(market.direction(0.01), "up")
        self.assertEqual(market.direction(-0.01), "down")

    def test_freshness_is_in_the_words_somebody_would_use(self):
        self.assertEqual(market.freshness(3), "just now")
        self.assertEqual(market.freshness(200), "3 min ago")
        self.assertEqual(market.freshness(3600), "1 hour ago")
        self.assertEqual(market.freshness(7200), "2 hours ago")
        self.assertEqual(market.freshness(90_000), "yesterday")
        self.assertEqual(market.freshness(300_000), "3 days ago")


class TestSearching(unittest.TestCase):
    def test_a_query_matches_the_front_of_a_name_or_a_symbol(self):
        bitcoin = market.parse(RECORD, 1)
        self.assertTrue(bitcoin.matches("bit"))
        self.assertTrue(bitcoin.matches("BTC"))
        self.assertTrue(bitcoin.matches(""))

    def test_a_query_does_not_match_the_middle_of_a_word(self):
        """Otherwise a search box fills up with coincidences."""
        bitcoin = market.parse(RECORD, 1)
        self.assertFalse(bitcoin.matches("itc"))
        self.assertFalse(bitcoin.matches("coin"))

    def test_a_query_matches_the_front_of_any_word_in_a_name(self):
        """ "cash" has to find Bitcoin Cash, the way a launcher works."""
        cash = market.parse({**RECORD, "id": "bch", "name": "Bitcoin Cash"}, 2)
        self.assertTrue(cash.matches("cash"))
        self.assertTrue(cash.matches("bit"))


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()
        return False


class TestLive(unittest.TestCase):
    def test_the_url_asks_for_what_the_app_draws(self):
        live = market.Live(currency="eur", count=50)
        url = live._url()
        self.assertIn("vs_currency=eur", url)
        self.assertIn("per_page=50", url)
        self.assertIn("order=market_cap_desc", url)
        # The sparkline is 168 prices a coin for a chart this app does not draw.
        self.assertIn("sparkline=false", url)

    def test_a_count_past_the_endpoints_ceiling_is_clamped(self):
        self.assertIn("per_page=250", market.Live(count=9999)._url())

    def test_asking_for_no_coins_by_name_makes_no_request(self):
        """Without `ids` this endpoint answers with the whole market."""
        with mock.patch.object(market.urllib.request, "urlopen") as opened:
            self.assertEqual(market.Live().by_ids([]), [])
        opened.assert_not_called()

    def _answer(self, payload):
        return mock.patch.object(
            market.urllib.request,
            "urlopen",
            return_value=FakeResponse(json.dumps(payload).encode()),
        )

    def test_a_good_answer_becomes_coins(self):
        with self._answer([RECORD]):
            coins = market.Live().markets()
        self.assertEqual([c.id for c in coins], ["bitcoin"])

    def test_a_rate_limit_says_so_and_says_when(self):
        error = urllib.error.HTTPError(
            "https://example",
            429,
            "Too Many Requests",
            {"Retry-After": "90"},
            io.BytesIO(b""),
        )
        # An HTTPError is a file object, and one that is garbage collected
        # unclosed prints a ResourceWarning into the middle of an otherwise
        # quiet test run.
        self.addCleanup(error.close)
        with (
            mock.patch.object(market.urllib.request, "urlopen", side_effect=error),
            self.assertRaises(MarketError) as caught,
        ):
            market.Live().markets()
        self.assertEqual(caught.exception.retry_after, 90.0)
        self.assertIn("rate-limit", str(caught.exception))

    def test_a_rate_limit_with_no_advice_still_says_when(self):
        """CoinGecko's own limit, rather than the general backoff: this is a
        wait to be served, not a phone that has lost signal."""
        error = urllib.error.HTTPError(
            "https://example", 429, "Too Many Requests", {}, io.BytesIO(b"")
        )
        self.addCleanup(error.close)
        with (
            mock.patch.object(market.urllib.request, "urlopen", side_effect=error),
            self.assertRaises(MarketError) as caught,
        ):
            market.Live().markets()
        self.assertEqual(caught.exception.retry_after, market.RATE_LIMIT_S)

    def test_a_body_that_is_not_json_is_a_sentence(self):
        with (
            mock.patch.object(
                market.urllib.request,
                "urlopen",
                return_value=FakeResponse(b"<html>maintenance</html>"),
            ),
            self.assertRaises(MarketError) as caught,
        ):
            market.Live().markets()
        self.assertIn("JSON", str(caught.exception))

    def test_no_network_is_one_sentence_whichever_way_it_failed(self):
        for failure in (
            urllib.error.URLError("unreachable"),
            TimeoutError("slow"),
            ConnectionResetError("reset"),
        ):
            with (
                mock.patch.object(
                    market.urllib.request, "urlopen", side_effect=failure
                ),
                self.assertRaises(MarketError) as caught,
            ):
                market.Live().markets()
            self.assertIn("No answer", str(caught.exception))


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
        self.assertTrue(store.toggle("monero"))
        store.save_favourites()

        reopened = self.store()
        reopened.load()
        self.assertEqual(reopened.favourites, ["monero"])
        self.assertTrue(reopened.is_favourite("monero"))

    def test_toggling_twice_leaves_nothing_behind(self):
        store = self.store()
        store.toggle("monero")
        self.assertFalse(store.toggle("monero"))
        self.assertEqual(store.favourites, [])

    def test_the_starred_page_is_in_the_order_things_were_starred(self):
        """Not rank order: a watchlist that sorts itself reorders under a thumb
        that is halfway down it."""
        store = self.store()
        store.replace(
            [
                coin("bitcoin", rank=1),
                coin("monero", rank=23),
                coin("dogecoin", rank=9),
            ],
            fetched=time.time(),
            currency="usd",
        )
        for identifier in ("monero", "bitcoin", "dogecoin"):
            store.toggle(identifier)
        self.assertEqual(
            [c.id for c in store.starred()], ["monero", "bitcoin", "dogecoin"]
        )

    def test_a_star_with_no_price_behind_it_is_not_drawn(self):
        store = self.store()
        store.toggle("monero")
        self.assertEqual(store.starred(), [])
        self.assertEqual(store.missing(), ["monero"])

    def test_a_duplicated_file_does_not_draw_a_coin_twice(self):
        (self.dir / "favourites.json").write_text(
            json.dumps({"favourites": ["monero", "monero", 7, ""]}), encoding="utf-8"
        )
        store = self.store()
        store.load()
        self.assertEqual(store.favourites, ["monero"])

    def test_a_file_that_cannot_be_read_is_moved_aside_rather_than_overwritten(self):
        """The broken copy is the only evidence of what the user actually had."""
        path = self.dir / "favourites.json"
        path.write_text("{not json", encoding="utf-8")
        store = self.store()
        store.load()
        self.assertEqual(store.favourites, [])
        self.assertFalse(path.exists())
        self.assertTrue(list(self.dir.glob("favourites.broken-*.json")))


class TestCache(StoreCase):
    def test_prices_survive_a_launch_with_no_signal(self):
        store = self.store()
        store.replace([coin("bitcoin")], fetched=1_000_000.0, currency="eur")
        store.save_market()

        reopened = self.store()
        reopened.load()
        self.assertEqual([c.id for c in reopened.coins], ["bitcoin"])
        self.assertEqual(reopened.currency, "eur")
        self.assertEqual(reopened.fetched, 1_000_000.0)

    def test_an_empty_answer_is_never_written_over_a_good_one(self):
        """ "We have never fetched" and "the market is empty" are different."""
        store = self.store()
        store.save_market()
        self.assertFalse((self.dir / "market.json").exists())

    def test_the_second_request_wins_and_the_ranking_is_kept(self):
        store = self.store()
        store.replace(
            [coin("bitcoin", rank=1, price=1.0), coin("monero", rank=23)],
            fetched=1.0,
            currency="usd",
        )
        store.replace(
            [coin("monero", rank=23), coin("bitcoin", rank=1, price=2.0)],
            fetched=2.0,
            currency="usd",
        )
        self.assertEqual([c.id for c in store.coins], ["bitcoin", "monero"])
        self.assertEqual(store.coins[0].price, 2.0)

    def test_prices_that_were_never_fetched_are_infinitely_old(self):
        self.assertEqual(self.store().age(), float("inf"))

    def test_a_clock_that_went_backwards_does_not_make_prices_from_the_future(self):
        """A phone that has just picked up NTP after a week off is the ordinary
        case, not a strange one."""
        store = self.store()
        store.fetched = 2_000.0
        self.assertEqual(store.age(now=1_000.0), 0.0)


if __name__ == "__main__":
    unittest.main()
