"""The file: what is written, what is read back, and what a bad one does.

No GTK here either. The interesting cases are all the ones where the file is not
what the app last wrote -- half a save, an edit by hand, a version from before
some field existed -- because on a phone the app is killed rather than closed,
and a file that has been written to by a dying process is the ordinary case.

The chess-specific one is the last group: the moves in the file are text, so
there are two ways for a move to be wrong rather than one. It can fail to be a
move at all (`e2e9`, `hello`), and it can be a perfectly well-formed move that
this position has no room for. Both end the game at the same place, and neither
is allowed to take the moves before it with them.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_chess.chess import BLACK, WHITE, Game, parse_uci  # noqa: E402
from moarchy_chess.store import (  # noqa: E402
    DRAWN,
    HOTSEAT,
    LOST,
    SOLO,
    WON,
    Store,
)

OPENING = ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6"]


def fresh() -> Store:
    return Store(Path(tempfile.mkdtemp()) / "chess.json")


def played(store: Store, moves=OPENING) -> Game:
    game = Game([parse_uci(m) for m in moves])
    store.remember(game)
    return game


class Roundtrip(unittest.TestCase):
    def test_an_untouched_store_has_an_opening_in_it(self):
        store = fresh()
        self.assertEqual(store.game().moves, [])
        self.assertEqual(store.mode, SOLO)
        self.assertEqual(store.human, WHITE)

    def test_a_game_survives_being_written_and_read(self):
        store = fresh()
        played(store)
        store.save()

        again = Store(store.path)
        again.load()
        self.assertEqual(again.moves, OPENING)
        self.assertEqual(again.game().uci(), OPENING)

    def test_the_settings_survive_too(self):
        store = fresh()
        store.begin(mode=HOTSEAT, level="hard", human=BLACK)
        store.save()

        again = Store(store.path)
        again.load()
        self.assertEqual(again.mode, HOTSEAT)
        self.assertEqual(again.level, "hard")
        self.assertEqual(again.human, BLACK)

    def test_the_moves_are_written_as_people_write_them(self):
        store = fresh()
        played(store)
        store.save()
        data = json.loads(store.path.read_text())
        self.assertEqual(data["game"]["moves"], OPENING)
        self.assertEqual(data["schema"], 1)

    def test_a_missing_file_is_not_an_error(self):
        store = Store(Path(tempfile.mkdtemp()) / "nothing" / "chess.json")
        store.load()
        self.assertEqual(store.moves, [])

    def test_saving_creates_the_directory(self):
        store = Store(Path(tempfile.mkdtemp()) / "made" / "up" / "chess.json")
        store.save()
        self.assertTrue(store.path.exists())


class BadFiles(unittest.TestCase):
    def write(self, text: str) -> Store:
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(text, encoding="utf-8")
        store.load()
        return store

    def test_a_file_that_is_not_json_is_moved_aside_rather_than_overwritten(self):
        store = self.write("{half a file")
        self.assertFalse(store.path.exists())
        self.assertTrue(list(store.path.parent.glob("*.broken-*.json")))

    def test_a_file_that_is_not_an_object_is_ignored(self):
        store = self.write("[1, 2, 3]")
        self.assertEqual(store.moves, [])

    def test_a_move_that_is_not_a_move_ends_the_game_there(self):
        store = self.write(
            json.dumps({"game": {"moves": ["e2e4", "e7e5", "wat", "g1f3"]}})
        )
        self.assertEqual(store.game().uci(), ["e2e4", "e7e5"])

    def test_a_move_that_will_not_play_ends_the_game_there(self):
        store = self.write(
            json.dumps({"game": {"moves": ["e2e4", "e7e5", "e2e4", "g1f3"]}})
        )
        self.assertEqual(store.game().uci(), ["e2e4", "e7e5"])

    def test_the_kept_part_is_what_gets_saved_back(self):
        store = self.write(json.dumps({"game": {"moves": ["e2e4", "nonsense"]}}))
        store.game()
        store.save()
        again = Store(store.path)
        again.load()
        self.assertEqual(again.moves, ["e2e4"])

    def test_moves_that_are_not_even_strings_are_dropped(self):
        store = self.write(json.dumps({"game": {"moves": ["e2e4", 12, None]}}))
        self.assertEqual(store.moves, ["e2e4"])

    def test_an_unknown_mode_or_level_falls_back(self):
        store = self.write(
            json.dumps({"game": {"mode": "postal", "level": "impossible"}})
        )
        self.assertEqual(store.mode, SOLO)
        self.assertEqual(store.level, "medium")

    def test_stats_for_a_level_that_does_not_exist_are_dropped(self):
        store = self.write(json.dumps({"stats": {"nightmare": {"played": 4}}}))
        self.assertEqual(store.stats, {})

    def test_negative_counts_are_clamped(self):
        store = self.write(json.dumps({"stats": {"easy": {"played": -3, "won": 2}}}))
        self.assertEqual(store.record_for("easy")["played"], 0)
        self.assertEqual(store.record_for("easy")[WON], 2)


class Record(unittest.TestCase):
    def test_a_win_goes_in_against_the_level_it_was_won_against(self):
        store = fresh()
        store.begin(mode=SOLO, level="hard", human=WHITE)
        store.record(WON, 31)
        self.assertEqual(store.record_for("hard")["played"], 1)
        self.assertEqual(store.record_for("hard")[WON], 1)
        self.assertEqual(store.record_for("hard")["quickest"], 31)

    def test_the_quickest_win_is_the_shortest_one(self):
        store = fresh()
        store.begin(mode=SOLO, level="easy", human=WHITE)
        store.record(WON, 40)
        store.record(WON, 22)
        store.record(WON, 55)
        self.assertEqual(store.record_for("easy")["quickest"], 22)

    def test_a_loss_does_not_set_a_quickest(self):
        store = fresh()
        store.begin(mode=SOLO, level="easy", human=WHITE)
        store.record(LOST, 9)
        self.assertEqual(store.record_for("easy")["quickest"], 0)

    def test_nothing_is_recorded_for_two_people_at_one_phone(self):
        store = fresh()
        store.begin(mode=HOTSEAT, level="medium", human=WHITE)
        store.record(WON, 20)
        self.assertEqual(store.totals()["played"], 0)

    def test_a_result_that_is_not_one_is_refused(self):
        store = fresh()
        store.begin(mode=SOLO, level="easy", human=WHITE)
        store.record("abandoned")
        self.assertEqual(store.totals()["played"], 0)

    def test_totals_add_up_across_levels(self):
        store = fresh()
        store.mode = SOLO
        for level, wins, losses in (("easy", 3, 1), ("medium", 1, 2)):
            store.level = level
            for _ in range(wins):
                store.record(WON, 30)
            for _ in range(losses):
                store.record(LOST)
        totals = store.totals()
        self.assertEqual(totals["played"], 7)
        self.assertEqual(totals[WON], 4)
        self.assertEqual(totals[LOST], 3)
        self.assertEqual(totals[DRAWN], 0)

    def test_the_record_survives_a_round_trip(self):
        store = fresh()
        store.begin(mode=SOLO, level="medium", human=WHITE)
        store.record(WON, 28)
        store.record(DRAWN)
        store.save()

        again = Store(store.path)
        again.load()
        self.assertEqual(again.record_for("medium")[WON], 1)
        self.assertEqual(again.record_for("medium")[DRAWN], 1)
        self.assertEqual(again.record_for("medium")["quickest"], 28)


class Beginning(unittest.TestCase):
    def test_a_new_game_clears_the_moves_but_not_the_record(self):
        store = fresh()
        store.mode = SOLO
        store.level = "easy"
        store.record(WON, 25)
        played(store)
        store.begin(mode=SOLO, level="medium", human=BLACK)
        self.assertEqual(store.moves, [])
        self.assertFalse(store.finished)
        self.assertEqual(store.record_for("easy")[WON], 1)

    def test_a_finished_game_is_remembered_as_finished(self):
        store = fresh()
        game = played(store)
        store.remember(game, finished=True)
        store.save()
        again = Store(store.path)
        again.load()
        self.assertTrue(again.finished)

    def test_a_nonsense_colour_becomes_white(self):
        store = fresh()
        store.begin(mode=SOLO, level="easy", human=7)
        self.assertEqual(store.human, WHITE)


class Writing(unittest.TestCase):
    def test_nothing_is_left_behind(self):
        store = fresh()
        played(store)
        store.save()
        self.assertEqual(
            sorted(p.name for p in store.path.parent.iterdir()), ["chess.json"]
        )

    def test_a_second_save_replaces_the_first(self):
        store = fresh()
        played(store, OPENING[:2])
        store.save()
        played(store, OPENING)
        store.save()
        again = Store(store.path)
        again.load()
        self.assertEqual(again.moves, OPENING)


if __name__ == "__main__":
    unittest.main()
