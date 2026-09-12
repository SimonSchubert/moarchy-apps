"""The file: what is written, what is read back, and what a bad one does.

No GTK here either. The interesting cases are all the ones where the file is not
what the app last wrote -- half a save, an edit by hand, a version from before
some field existed -- because on a phone the app is killed rather than closed,
and a file that has been written to by a dying process is the ordinary case.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_reversi.reversi import DARK, LIGHT, OPENING, Game, index  # noqa: E402
from moarchy_reversi.store import (  # noqa: E402
    DRAWN,
    HOTSEAT,
    LOST,
    SOLO,
    WON,
    Store,
)


def fresh() -> Store:
    return Store(Path(tempfile.mkdtemp()) / "reversi.json")


def played(store: Store, plies: int = 6) -> Game:
    """A game of the first legal move each time -- short, and always the same."""
    game = Game()
    for _ in range(plies):
        game.play(game.position.legal()[0])
    store.remember(game)
    return game


class TestDefaults(unittest.TestCase):
    def test_a_missing_file_is_a_new_game_and_not_an_error(self):
        store = fresh()
        store.load()
        self.assertEqual(store.moves, [])
        self.assertEqual(store.game().position, OPENING)
        self.assertEqual(store.mode, SOLO)
        self.assertEqual(store.human, DARK)

    def test_a_new_game_starts_from_the_opening(self):
        store = fresh()
        played(store)
        game = store.begin(mode=SOLO, level="hard", human=LIGHT)
        self.assertEqual(game.position, OPENING)
        self.assertEqual(store.moves, [])
        self.assertFalse(store.finished)


class TestRoundTrip(unittest.TestCase):
    def test_a_game_comes_back_as_the_same_board(self):
        store = fresh()
        game = played(store, 10)
        store.save()

        again = Store(store.path)
        again.load()
        self.assertEqual(again.game().position, game.position)

    def test_the_settings_come_back_too(self):
        store = fresh()
        store.begin(mode=HOTSEAT, level="hard", human=LIGHT)
        store.save()

        again = Store(store.path)
        again.load()
        self.assertEqual(again.mode, HOTSEAT)
        self.assertEqual(again.level, "hard")
        self.assertEqual(again.human, LIGHT)

    def test_the_record_comes_back_too(self):
        store = fresh()
        store.level = "medium"
        store.record(WON, 12)
        store.record(LOST)
        store.save()

        again = Store(store.path)
        again.load()
        self.assertEqual(again.record_for("medium")["played"], 2)
        self.assertEqual(again.record_for("medium")["best"], 12)

    def test_saving_leaves_no_half_written_file_behind(self):
        store = fresh()
        played(store)
        store.save()
        self.assertEqual(
            [p.name for p in store.path.parent.iterdir()], [store.path.name]
        )

    def test_what_is_written_is_a_list_of_moves_a_person_could_read(self):
        store = fresh()
        played(store, 4)
        store.save()
        data = json.loads(store.path.read_text())
        self.assertEqual(data["schema"], 1)
        self.assertEqual(data["game"]["moves"], store.moves)


class TestDamagedFiles(unittest.TestCase):
    def test_a_move_that_will_not_play_ends_the_game_there(self):
        store = fresh()
        game = played(store, 6)
        legal = list(store.moves)
        store.moves = [*legal, index(0, 0)]  # a1 closes nothing at this point
        self.assertEqual(store.game().position, game.position)
        self.assertEqual(store.moves, legal)

    def test_a_move_list_of_nonsense_is_simply_a_new_game(self):
        store = fresh()
        store.moves = [999, -4, 17]
        self.assertEqual(store.game().position, OPENING)
        self.assertEqual(store.moves, [])

    def test_a_file_that_is_not_json_is_moved_aside_rather_than_overwritten(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text("{ this is not json", encoding="utf-8")
        store.load()
        self.assertFalse(store.path.exists())
        spare = list(store.path.parent.glob("*.broken-*.json"))
        self.assertEqual(len(spare), 1)
        self.assertIn("not json", spare[0].read_text())

    def test_a_file_that_is_not_even_a_table_is_ignored(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text("[1, 2, 3]", encoding="utf-8")
        store.load()
        self.assertEqual(store.moves, [])

    def test_a_level_that_no_longer_exists_falls_back(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps({"game": {"level": "impossible", "mode": "duel"}}),
            encoding="utf-8",
        )
        store.load()
        self.assertEqual(store.mode, SOLO)
        self.assertIn(store.level, ("easy", "medium", "hard"))

    def test_a_record_with_negative_numbers_in_it_is_cleaned_up(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps({"stats": {"easy": {"played": -5, "won": "lots"}}}),
            encoding="utf-8",
        )
        store.load()
        self.assertEqual(store.record_for("easy")["played"], 0)
        self.assertEqual(store.record_for("easy")[WON], 0)


class TestTheRecord(unittest.TestCase):
    def test_a_win_is_counted_against_the_level_it_was_won_at(self):
        store = fresh()
        store.begin(mode=SOLO, level="hard", human=DARK)
        store.record(WON, 20)
        self.assertEqual(store.record_for("hard")[WON], 1)
        self.assertEqual(store.record_for("easy")["played"], 0)

    def test_the_best_win_is_the_biggest_margin_not_the_last(self):
        store = fresh()
        store.begin(mode=SOLO, level="easy", human=DARK)
        store.record(WON, 30)
        store.record(WON, 4)
        self.assertEqual(store.record_for("easy")["best"], 30)

    def test_a_loss_does_not_count_as_a_best_win(self):
        store = fresh()
        store.begin(mode=SOLO, level="easy", human=DARK)
        store.record(LOST, 40)
        self.assertEqual(store.record_for("easy")["best"], 0)

    def test_two_people_on_one_phone_are_not_in_the_record(self):
        """The tally answers "how am I doing against Medium". Two people across
        a table have no answer to put in it."""
        store = fresh()
        store.begin(mode=HOTSEAT, level="medium", human=DARK)
        store.record(WON, 10)
        self.assertEqual(store.totals()["played"], 0)

    def test_something_that_is_not_a_result_is_not_recorded(self):
        store = fresh()
        store.record("abandoned")
        self.assertEqual(store.totals()["played"], 0)

    def test_the_totals_add_the_levels_up(self):
        store = fresh()
        for level, result in (("easy", WON), ("medium", LOST), ("hard", DRAWN)):
            store.level = level
            store.record(result, 6)
        totals = store.totals()
        self.assertEqual(totals["played"], 3)
        self.assertEqual((totals[WON], totals[LOST], totals[DRAWN]), (1, 1, 1))
        self.assertEqual(totals["best"], 6)


if __name__ == "__main__":
    unittest.main()
