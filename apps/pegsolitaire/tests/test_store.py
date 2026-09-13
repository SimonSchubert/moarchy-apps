"""The file: what is written, what is read back, and what a bad one does.

No GTK here either. The interesting cases are the ones where the file is not
what the app last wrote, because on a phone the app is killed rather than
closed.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_pegsolitaire.pegs import UP, Game, encode, index  # noqa: E402
from moarchy_pegsolitaire.store import Store, figure_label  # noqa: E402


def fresh() -> Store:
    return Store(Path(tempfile.mkdtemp()) / "pegsolitaire.json")


def played(store: Store, jumps: int = 4) -> Game:
    game = Game(store.figure)
    for _ in range(jumps):
        moves = game.position.moves()
        if not moves:
            break
        game.play(moves[0])
    store.remember(game)
    return game


class TestDefaults(unittest.TestCase):
    def test_a_missing_file_is_the_english_board_and_not_an_error(self):
        store = fresh()
        store.load()
        self.assertEqual(store.figure, "english")
        self.assertEqual(store.moves, [])
        self.assertEqual(store.game().count, 32)

    def test_a_new_figure_starts_from_its_own_beginning(self):
        store = fresh()
        played(store)
        game = store.begin("cross")
        self.assertEqual(game.figure.key, "cross")
        self.assertEqual(store.moves, [])
        self.assertFalse(store.finished)

    def test_starting_again_keeps_the_figure(self):
        store = fresh()
        store.begin("pyramid")
        played(store)
        game = store.again()
        self.assertEqual(game.figure.key, "pyramid")
        self.assertEqual(store.moves, [])


class TestRoundTrip(unittest.TestCase):
    def test_everything_written_comes_back(self):
        store = fresh()
        store.begin("diamond")
        game = played(store)
        store.record(3)
        store.save()

        back = Store(store.path)
        back.load()
        self.assertEqual(back.figure, "diamond")
        self.assertEqual(back.moves, list(game.moves))
        self.assertEqual(back.game().position, game.position)
        self.assertEqual(back.record_for("diamond")["best"], 3)
        self.assertTrue(back.recorded)

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

    def test_a_jump_that_will_not_play_ends_the_game_there(self):
        store = fresh()
        game = played(store, 3)
        # Jumping upwards out of the top row: off the board from any position
        # this game can be in, which is what makes it a tail and not a move.
        store.moves.append(encode(index(0, 2), UP))
        store.save()
        back = Store(store.path)
        back.load()
        self.assertEqual(back.game().position, game.position)
        self.assertEqual(len(back.moves), len(game.moves))

    def test_junk_in_the_fields_falls_back_rather_than_raising(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps(
                {
                    "game": {"figure": "rhombus", "moves": "several"},
                    "stats": {"english": {"best": "three"}, "rhombus": {"best": 2}},
                }
            ),
            encoding="utf-8",
        )
        store.load()
        self.assertEqual(store.figure, "english")
        self.assertEqual(store.moves, [])
        self.assertEqual(store.record_for("english")["best"], 0)
        self.assertEqual(store.record_for("rhombus")["best"], 0)

    def test_a_file_that_is_not_an_object_is_ignored(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text("[1, 2, 3]", encoding="utf-8")
        store.load()
        self.assertEqual(store.moves, [])


class TestTheRecord(unittest.TestCase):
    def test_fewest_pegs_only_ever_goes_down(self):
        store = fresh()
        store.begin("english")
        store.record(5)
        self.assertEqual(store.record_for("english")["best"], 5)
        store.record(8)
        self.assertEqual(store.record_for("english")["best"], 5)
        store.record(2)
        self.assertEqual(store.record_for("english")["best"], 2)

    def test_finishing_and_finishing_in_the_middle_are_counted_apart(self):
        store = fresh()
        store.begin("english")
        store.record(1)
        self.assertEqual(store.record_for("english")["solved"], 1)
        self.assertEqual(store.record_for("english")["perfect"], 0)
        store.record(1, perfect=True)
        self.assertEqual(store.record_for("english")["solved"], 2)
        self.assertEqual(store.record_for("english")["perfect"], 1)

    def test_a_board_with_no_pegs_on_it_is_not_a_result(self):
        store = fresh()
        store.record(0)
        self.assertEqual(store.record_for("english")["played"], 0)

    def test_the_figures_are_counted_apart(self):
        store = fresh()
        store.begin("cross")
        store.record(1)
        store.begin("plus")
        store.record(4)
        self.assertEqual(store.record_for("cross")["solved"], 1)
        self.assertEqual(store.record_for("plus")["solved"], 0)

    def test_totals_count_the_figures_that_have_been_finished(self):
        store = fresh()
        for key, left in (("cross", 1), ("plus", 1), ("pyramid", 3)):
            store.begin(key)
            store.record(left)
        totals = store.totals()
        self.assertEqual(totals["played"], 3)
        self.assertEqual(totals["solved"], 2)
        self.assertEqual(totals["best"], 2)

    def test_a_figure_has_a_name_to_put_on_a_row(self):
        self.assertEqual(figure_label("english"), "English board")
        self.assertEqual(figure_label("nonsense"), "English board")


if __name__ == "__main__":
    unittest.main()
