"""The file: what is written, what is read back, and what a bad one does.

No GTK here either. The interesting cases are all the ones where the file is not
what the app last wrote -- half a save, an edit by hand, a version from before
some field existed -- because on a phone the app is killed rather than closed.

The case this app has that the others do not is **the deck**. Fifty-two integers
is the one field where a corrupt file can describe something that is not merely
wrong but impossible, and a deck with two aces of spades in it must not be
loaded at all: a card game that quietly deals one is a card game whose rules
stop meaning anything, twenty moves later, with no error anywhere.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_solitaire.klondike import (  # noqa: E402
    DECK,
    STOCK,
    WASTE,
    Game,
    Move,
)
from moarchy_solitaire.store import LOST, WON, Store  # noqa: E402


def fresh() -> Store:
    return Store(Path(tempfile.mkdtemp()) / "solitaire.json")


def played(store: Store, deals: int = 3) -> Game:
    game = Game(store.deck, store.draw)
    for _ in range(deals):
        game.play(Move(STOCK, WASTE, min(game.draw, len(game.table.stock))))
    store.remember(game)
    return game


class TestDefaults(unittest.TestCase):
    def test_a_missing_file_is_a_fresh_deal_and_not_an_error(self):
        store = fresh()
        store.load()
        self.assertEqual(store.moves, [])
        self.assertEqual(sorted(store.deck), list(range(DECK)))
        self.assertEqual(store.draw, 1)

    def test_a_new_game_deals_a_different_pack(self):
        store = fresh()
        first = store.deck
        played(store)
        store.begin(draw=3)
        self.assertEqual(store.moves, [])
        self.assertEqual(store.draw, 3)
        self.assertNotEqual(store.deck, first)

    def test_dealing_again_keeps_the_pack(self):
        store = fresh()
        deck = store.deck
        played(store)
        store.again()
        self.assertEqual(store.deck, deck)
        self.assertEqual(store.moves, [])
        self.assertFalse(store.recorded)


class TestRoundTrip(unittest.TestCase):
    def test_everything_written_comes_back(self):
        store = fresh()
        store.begin(draw=3)
        game = played(store)
        store.record(WON, 140)
        store.save()

        back = Store(store.path)
        back.load()
        self.assertEqual(back.deck, store.deck)
        self.assertEqual(back.draw, 3)
        self.assertEqual(len(back.moves), len(game.moves))
        self.assertEqual(back.game().table, game.table)
        self.assertEqual(back.record_for(3)[WON], 1)
        self.assertEqual(back.record_for(3)["best"], 140)

    def test_the_table_is_replayed_rather_than_stored(self):
        store = fresh()
        game = played(store, deals=8)
        store.save()
        back = Store(store.path)
        back.load()
        self.assertEqual(back.game().table, game.table)

    def test_a_save_leaves_no_temporary_file_behind(self):
        store = fresh()
        store.save()
        self.assertEqual(
            [p.name for p in store.path.parent.iterdir()], [store.path.name]
        )


class TestABadFile(unittest.TestCase):
    def test_nonsense_is_moved_aside_rather_than_overwritten(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text("{not json", encoding="utf-8")
        store.load()
        spare = list(store.path.parent.glob("*.broken-*.json"))
        self.assertEqual(len(spare), 1)
        self.assertEqual(spare[0].read_text(encoding="utf-8"), "{not json")

    def test_a_deck_with_a_card_twice_is_not_a_deck(self):
        store = fresh()
        mine = store.deck
        bad = list(mine)
        bad[0] = bad[1]
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(json.dumps({"game": {"deck": bad}}), encoding="utf-8")
        store.load()
        self.assertEqual(sorted(store.deck), list(range(DECK)))

    def test_a_short_deck_is_not_a_deck_either(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps({"game": {"deck": list(range(40))}}), encoding="utf-8"
        )
        store.load()
        self.assertEqual(sorted(store.deck), list(range(DECK)))

    def test_a_move_that_will_not_play_ends_the_game_there(self):
        store = fresh()
        game = played(store, deals=4)
        store.moves.append([6, 2, 9])
        store.save()
        back = Store(store.path)
        back.load()
        self.assertEqual(back.game().table, game.table)
        self.assertEqual(len(back.moves), len(game.moves))

    def test_junk_in_the_fields_falls_back_rather_than_raising(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps(
                {
                    "game": {"draw": 7, "moves": "lots", "deck": "cards"},
                    "stats": {"draw1": {"played": "many"}},
                }
            ),
            encoding="utf-8",
        )
        store.load()
        self.assertEqual(store.draw, 1)
        self.assertEqual(store.moves, [])
        self.assertEqual(store.record_for(1)["played"], 0)

    def test_a_file_that_is_not_an_object_is_ignored(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text("[1, 2, 3]", encoding="utf-8")
        store.load()
        self.assertEqual(store.moves, [])


class TestTheRecord(unittest.TestCase):
    def test_the_two_deals_are_counted_apart(self):
        store = fresh()
        store.begin(draw=1)
        store.record(WON, 120)
        store.begin(draw=3)
        store.record(LOST)
        self.assertEqual(store.record_for(1)[WON], 1)
        self.assertEqual(store.record_for(3)[WON], 0)
        self.assertEqual(store.record_for(3)["played"], 1)

    def test_fewest_moves_only_ever_goes_down(self):
        store = fresh()
        store.begin(draw=1)
        store.record(WON, 180)
        self.assertEqual(store.record_for(1)["best"], 180)
        store.record(WON, 210)
        self.assertEqual(store.record_for(1)["best"], 180)
        store.record(WON, 150)
        self.assertEqual(store.record_for(1)["best"], 150)

    def test_a_run_of_wins_grows_and_a_loss_ends_it(self):
        store = fresh()
        store.begin(draw=1)
        for _ in range(4):
            store.record(WON, 200)
        self.assertEqual(store.record_for(1)["longest"], 4)
        store.record(LOST)
        self.assertEqual(store.record_for(1)["streak"], 0)
        self.assertEqual(store.record_for(1)["longest"], 4)

    def test_recording_marks_the_game_as_counted(self):
        store = fresh()
        self.assertFalse(store.recorded)
        store.record(WON, 100)
        self.assertTrue(store.recorded)
        store.begin(draw=1)
        self.assertFalse(store.recorded)

    def test_a_result_that_is_not_one_is_ignored(self):
        store = fresh()
        store.record("abandoned")
        self.assertEqual(store.record_for(1)["played"], 0)

    def test_totals_add_the_deals_up_and_take_the_fewest_moves(self):
        store = fresh()
        store.begin(draw=1)
        store.record(WON, 175)
        store.begin(draw=3)
        store.record(WON, 240)
        store.record(LOST)
        totals = store.totals()
        self.assertEqual(totals["played"], 3)
        self.assertEqual(totals[WON], 2)
        self.assertEqual(totals["best"], 175)


if __name__ == "__main__":
    unittest.main()
