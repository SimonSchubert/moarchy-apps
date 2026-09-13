"""The file: what is written, what is read back, and what a bad one does.

No GTK here either. The case this app has that the others do not is the clock:
it is accumulated seconds rather than a start time, because the thing being
measured stops and starts, and a start time would have to be corrected every
time the window lost focus.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_minesweeper.minesweeper import index, level_for  # noqa: E402
from moarchy_minesweeper.store import LOST, WON, Store, clock  # noqa: E402


def fresh() -> Store:
    return Store(Path(tempfile.mkdtemp()) / "minesweeper.json")


def played(store: Store) -> None:
    game = store.game()
    level = level_for(store.level)
    game.tap(index(level.height // 2, level.width // 2, level.width))
    game.mark(0)
    store.remember(game)


class TestDefaults(unittest.TestCase):
    def test_a_missing_file_is_a_fresh_board_and_not_an_error(self):
        store = fresh()
        store.load()
        self.assertEqual(store.level, "standard")
        self.assertEqual(store.moves, [])
        self.assertEqual(store.seconds, 0)
        self.assertFalse(store.game().started)

    def test_a_new_game_at_a_new_level_resets_the_clock(self):
        store = fresh()
        played(store)
        store.seconds = 90
        store.begin("gentle")
        self.assertEqual(store.level, "gentle")
        self.assertEqual(store.seconds, 0)
        self.assertEqual(store.moves, [])

    def test_the_same_seed_can_be_asked_for_again(self):
        store = fresh()
        seed = store.seed
        played(store)
        store.begin(store.level, seed=seed)
        self.assertEqual(store.seed, seed)
        self.assertEqual(store.moves, [])


class TestRoundTrip(unittest.TestCase):
    def test_everything_written_comes_back(self):
        store = fresh()
        store.begin("gentle")
        played(store)
        store.seconds = 42
        store.record(WON, 42)
        store.save()

        back = Store(store.path)
        back.load()
        self.assertEqual(back.level, "gentle")
        self.assertEqual(back.seed, store.seed)
        self.assertEqual(back.seconds, 42)
        self.assertEqual(back.moves, store.moves)
        self.assertEqual(back.record_for("gentle")["best"], 42)

    def test_the_board_comes_back_with_the_same_mines_under_it(self):
        store = fresh()
        store.begin("gentle")
        played(store)
        game = store.game()
        store.save()
        back = Store(store.path)
        back.load()
        self.assertEqual(back.game().field.mines, game.field.mines)
        self.assertEqual(back.game().opened, game.opened)

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
        self.assertEqual(len(list(store.path.parent.glob("*.broken-*.json"))), 1)

    def test_junk_in_the_fields_falls_back_rather_than_raising(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps(
                {
                    "game": {
                        "level": "impossible",
                        "seed": "cheese",
                        "seconds": -5,
                        "moves": "many",
                    },
                    "stats": {"gentle": {"best": "quick"}},
                }
            ),
            encoding="utf-8",
        )
        store.load()
        self.assertEqual(store.level, "standard")
        self.assertEqual(store.moves, [])
        self.assertEqual(store.seconds, 0)
        self.assertEqual(store.record_for("gentle")["best"], 0)

    def test_a_move_that_will_not_play_ends_the_game_there(self):
        store = fresh()
        store.begin("gentle")
        played(store)
        good = list(store.moves)
        store.moves = [*good, 99999]
        store.save()
        back = Store(store.path)
        back.load()
        self.assertEqual(back.game().moves, good)

    def test_a_file_that_is_not_an_object_is_ignored(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text("[1, 2, 3]", encoding="utf-8")
        store.load()
        self.assertEqual(store.moves, [])


class TestTheRecord(unittest.TestCase):
    def test_the_fastest_clear_only_goes_down(self):
        store = fresh()
        store.begin("gentle")
        store.record(WON, 90)
        self.assertEqual(store.record_for("gentle")["best"], 90)
        store.record(WON, 120)
        self.assertEqual(store.record_for("gentle")["best"], 90)
        store.record(WON, 61)
        self.assertEqual(store.record_for("gentle")["best"], 61)

    def test_a_loss_does_not_set_a_time(self):
        store = fresh()
        store.begin("gentle")
        store.record(LOST, 12)
        self.assertEqual(store.record_for("gentle")["best"], 0)
        self.assertEqual(store.record_for("gentle")["played"], 1)

    def test_a_run_of_wins_grows_and_a_loss_ends_it(self):
        store = fresh()
        store.begin("hard")
        for _ in range(3):
            store.record(WON, 300)
        self.assertEqual(store.record_for("hard")["longest"], 3)
        store.record(LOST)
        self.assertEqual(store.record_for("hard")["streak"], 0)
        self.assertEqual(store.record_for("hard")["longest"], 3)

    def test_the_levels_are_counted_apart(self):
        store = fresh()
        store.begin("gentle")
        store.record(WON, 30)
        store.begin("hard")
        store.record(LOST)
        self.assertEqual(store.record_for("gentle")[WON], 1)
        self.assertEqual(store.record_for("hard")[WON], 0)

    def test_a_result_that_is_not_one_is_ignored(self):
        store = fresh()
        store.record("abandoned")
        self.assertEqual(store.record_for("standard")["played"], 0)


class TestTheClock(unittest.TestCase):
    def test_it_reads_as_minutes_and_seconds(self):
        self.assertEqual(clock(0), "0:00")
        self.assertEqual(clock(9), "0:09")
        self.assertEqual(clock(61), "1:01")
        self.assertEqual(clock(599), "9:59")

    def test_it_does_not_wrap_round_at_an_hour(self):
        # A game left open over a lunch break is an ordinary thing, and a clock
        # that silently went back to 0:07 would be worse than a long one.
        self.assertEqual(clock(3600), "1:00:00")
        self.assertEqual(clock(3725), "1:02:05")

    def test_nonsense_is_not_a_negative_clock(self):
        self.assertEqual(clock(-5), "0:00")


if __name__ == "__main__":
    unittest.main()
