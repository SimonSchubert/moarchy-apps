"""The file: what is written, what is read back, and what a bad one does.

No GTK here either. The interesting cases are all the ones where the file is not
what the app last wrote -- half a save, an edit by hand, a version from before
some field existed -- because on a phone the app is killed rather than closed,
and a file written to by a dying process is the ordinary case.

The case that is this app's own is the series: it survives a rematch and does
not survive a new game, and getting that backwards is a score line that either
resets every fifteen seconds or never resets at all.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_tictactoe.store import (  # noqa: E402
    DRAWN,
    HOTSEAT,
    LOST,
    SOLO,
    WON,
    Store,
)
from moarchy_tictactoe.tictactoe import CROSS, EMPTY, NOUGHT, Game  # noqa: E402


def fresh() -> Store:
    return Store(Path(tempfile.mkdtemp()) / "tictactoe.json")


def played(store: Store, moves=(4, 0, 8)) -> Game:
    game = Game()
    for cell in moves:
        game.play(cell)
    store.remember(game)
    return game


class TestDefaults(unittest.TestCase):
    def test_a_missing_file_is_a_new_game_and_not_an_error(self):
        store = fresh()
        store.load()
        self.assertEqual(store.moves, [])
        self.assertEqual(store.game().position, EMPTY)
        self.assertEqual(store.mode, SOLO)
        self.assertEqual(store.mark, CROSS)
        self.assertEqual(store.series, {"a": 0, "b": 0, DRAWN: 0})

    def test_a_new_game_starts_from_an_empty_board(self):
        store = fresh()
        played(store)
        game = store.begin(mode=SOLO, level="perfect", mark=NOUGHT)
        self.assertEqual(game.position, EMPTY)
        self.assertEqual(store.moves, [])
        self.assertFalse(store.finished)
        self.assertEqual(store.mark, NOUGHT)


class TestRoundTrip(unittest.TestCase):
    def test_everything_written_comes_back(self):
        store = fresh()
        store.begin(mode=HOTSEAT, level="easy", mark=NOUGHT)
        played(store, (0, 4, 8))
        store.record(WON)
        store.save()

        back = Store(store.path)
        back.load()
        self.assertEqual(back.moves, [0, 4, 8])
        self.assertEqual(back.mode, HOTSEAT)
        self.assertEqual(back.level, "easy")
        self.assertEqual(back.mark, NOUGHT)
        self.assertEqual(back.series["a"], 1)

    def test_the_board_is_replayed_rather_than_stored(self):
        store = fresh()
        game = played(store, (0, 3, 1, 4, 2))
        store.save()
        back = Store(store.path)
        back.load()
        self.assertEqual(back.game().position, game.position)
        self.assertEqual(back.game().position.winner(), CROSS)

    def test_whether_a_result_was_counted_survives_the_file(self):
        # The flag the window reads on the way back in. It is not the same
        # question as "is the board finished": the move that ends a game is
        # written the instant it is played and counted a moment later, so a
        # phone killed between the two has a finished game and an uncounted one.
        store = fresh()
        store.begin(mode=SOLO, level="fair", mark=CROSS)
        store.remember(Game([0, 3, 1, 4, 2]), finished=True)
        store.save()
        back = Store(store.path)
        back.load()
        self.assertTrue(back.finished)
        self.assertFalse(back.recorded)

        back.record(WON)
        back.save()
        again = Store(store.path)
        again.load()
        self.assertTrue(again.recorded)

    def test_a_rematch_owes_its_result_again(self):
        store = fresh()
        store.begin(mode=SOLO, level="fair", mark=CROSS)
        store.record(WON)
        self.assertTrue(store.recorded)
        store.rematch()
        self.assertFalse(store.recorded)

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
        self.assertEqual(store.moves, [])
        spare = list(store.path.parent.glob("*.broken-*.json"))
        self.assertEqual(len(spare), 1)
        self.assertEqual(spare[0].read_text(encoding="utf-8"), "{not json")

    def test_a_move_that_will_not_play_ends_the_game_there(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps({"game": {"moves": [4, 4, 0]}}), encoding="utf-8"
        )
        store.load()
        self.assertEqual(store.game().moves, [4])
        self.assertEqual(store.moves, [4])

    def test_a_board_that_could_not_be_reached_cannot_be_loaded(self):
        # Five X marks and no O. Loading is playing, so it stops at the first
        # move that is not somebody's turn -- which here is the second one.
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps({"game": {"moves": [0, 1, 2, 3, 4]}}), encoding="utf-8"
        )
        store.load()
        game = store.game()
        self.assertLessEqual(
            abs(
                game.position.marks(CROSS).bit_count()
                - game.position.marks(NOUGHT).bit_count()
            ),
            1,
        )

    def test_junk_in_the_fields_falls_back_rather_than_raising(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps(
                {
                    "game": {
                        "mode": "telepathy",
                        "level": "impossible",
                        "mark": 17,
                        "moves": "4",
                    },
                    "series": "none",
                    "stats": {"easy": {"played": "lots"}},
                }
            ),
            encoding="utf-8",
        )
        store.load()
        self.assertEqual(store.mode, SOLO)
        self.assertEqual(store.level, "fair")
        self.assertEqual(store.mark, CROSS)
        self.assertEqual(store.moves, [])
        self.assertEqual(store.series[DRAWN], 0)
        self.assertEqual(store.record_for("easy")["played"], 0)

    def test_a_file_that_is_not_an_object_is_ignored(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text("[1, 2, 3]", encoding="utf-8")
        store.load()
        self.assertEqual(store.moves, [])


class TestTheSeries(unittest.TestCase):
    def test_a_rematch_swaps_the_marks_and_keeps_the_score(self):
        store = fresh()
        store.begin(mode=SOLO, level="fair", mark=CROSS)
        store.record(WON)
        played(store)
        store.rematch()
        self.assertEqual(store.mark, NOUGHT)
        self.assertEqual(store.moves, [])
        self.assertEqual(store.series["a"], 1)
        store.rematch()
        self.assertEqual(store.mark, CROSS)

    def test_a_new_game_starts_a_new_series(self):
        store = fresh()
        store.begin(mode=SOLO, level="fair", mark=CROSS)
        store.record(WON)
        store.record(DRAWN)
        store.begin(mode=SOLO, level="easy", mark=CROSS)
        self.assertEqual(store.series, {"a": 0, "b": 0, DRAWN: 0})

    def test_both_modes_keep_a_series(self):
        store = fresh()
        store.begin(mode=HOTSEAT, level="fair", mark=CROSS)
        store.record(LOST)
        store.record(LOST)
        self.assertEqual(store.series["b"], 2)

    def test_a_result_that_is_not_one_is_ignored(self):
        store = fresh()
        store.record("abandoned")
        self.assertEqual(store.series, {"a": 0, "b": 0, DRAWN: 0})


class TestTheRecord(unittest.TestCase):
    def test_only_the_computers_games_are_recorded(self):
        store = fresh()
        store.begin(mode=HOTSEAT, level="fair", mark=CROSS)
        store.record(WON)
        self.assertEqual(store.record_for("fair")["played"], 0)
        self.assertEqual(store.series["a"], 1)

    def test_a_run_without_losing_grows_and_a_loss_ends_it(self):
        store = fresh()
        store.begin(mode=SOLO, level="perfect", mark=CROSS)
        for _ in range(5):
            store.record(DRAWN)
        self.assertEqual(store.record_for("perfect")["unbeaten"], 5)
        self.assertEqual(store.record_for("perfect")["best"], 5)
        store.record(LOST)
        self.assertEqual(store.record_for("perfect")["unbeaten"], 0)
        self.assertEqual(store.record_for("perfect")["best"], 5)
        store.record(WON)
        self.assertEqual(store.record_for("perfect")["unbeaten"], 1)
        self.assertEqual(store.record_for("perfect")["best"], 5)

    def test_totals_add_the_levels_up_and_take_the_best_run(self):
        store = fresh()
        store.begin(mode=SOLO, level="easy", mark=CROSS)
        for _ in range(4):
            store.record(WON)
        store.level = "perfect"
        for _ in range(9):
            store.record(DRAWN)
        totals = store.totals()
        self.assertEqual(totals["played"], 13)
        self.assertEqual(totals[WON], 4)
        self.assertEqual(totals["best"], 9)

    def test_an_empty_record_is_a_record_of_nothing(self):
        self.assertEqual(fresh().record_for("fair")["played"], 0)


if __name__ == "__main__":
    unittest.main()
