"""The file: what is written, what is read back, and what a bad one does.

No GTK here either. The case this game has that Reversi does not is the
removal: a turn that closes a mill is two entries in the move list, so a file
truncated between them describes a board where somebody is owed a piece -- which
is a legal state, replays exactly, and is the one the loader has to be able to
come back to.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

from moarchy_mill.mill import (  # noqa: E402
    BLACK,
    OPENING,
    WHITE,
    Game,
    place_move,
)
from moarchy_mill.store import (  # noqa: E402
    DRAWN,
    HOTSEAT,
    LOST,
    SOLO,
    WON,
    Store,
)

# Four placements and then the one that closes a mill for white.
MILLED = [place_move(0), place_move(8), place_move(1), place_move(9), place_move(2)]


def fresh() -> Store:
    return Store(Path(tempfile.mkdtemp()) / "mill.json")


def played(store: Store, moves=None) -> Game:
    game = Game(moves if moves is not None else MILLED[:4])
    store.remember(game)
    return game


class TestDefaults(unittest.TestCase):
    def test_a_missing_file_is_a_new_game_and_not_an_error(self):
        store = fresh()
        store.load()
        self.assertEqual(store.moves, [])
        self.assertEqual(store.game().position, OPENING)
        self.assertEqual(store.mode, SOLO)
        self.assertEqual(store.human, WHITE)

    def test_a_new_game_starts_from_the_opening(self):
        store = fresh()
        played(store)
        game = store.begin(mode=SOLO, level="hard", human=BLACK)
        self.assertEqual(game.position, OPENING)
        self.assertEqual(store.moves, [])
        self.assertFalse(store.finished)
        self.assertFalse(store.recorded)
        self.assertEqual(store.human, BLACK)


class TestRoundTrip(unittest.TestCase):
    def test_everything_written_comes_back(self):
        store = fresh()
        store.begin(mode=HOTSEAT, level="easy", human=BLACK)
        game = played(store)
        store.save()

        back = Store(store.path)
        back.load()
        self.assertEqual(back.moves, list(game.moves))
        self.assertEqual(back.mode, HOTSEAT)
        self.assertEqual(back.level, "easy")
        self.assertEqual(back.human, BLACK)
        self.assertEqual(back.game().position, game.position)

    def test_a_turn_that_owes_a_removal_survives_the_file(self):
        # Five moves: four placements and the one that closes a mill. The board
        # this loads is one where white is still to move and owes a piece, and
        # it has to come back exactly that way.
        store = fresh()
        game = played(store, MILLED)
        self.assertTrue(game.position.removing)
        store.save()
        back = Store(store.path)
        back.load()
        resumed = back.game()
        self.assertTrue(resumed.position.removing)
        self.assertEqual(resumed.position.turn, WHITE)
        self.assertEqual(resumed.position, game.position)

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

    def test_a_move_that_will_not_play_ends_the_game_there(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps({"game": {"moves": [0, 0, 8]}}), encoding="utf-8"
        )
        store.load()
        self.assertEqual(store.game().moves, [0])
        self.assertEqual(store.moves, [0])

    def test_junk_in_the_fields_falls_back_rather_than_raising(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text(
            json.dumps(
                {
                    "game": {
                        "mode": "telepathy",
                        "level": "impossible",
                        "human": 17,
                        "moves": "8",
                    },
                    "stats": {"easy": {"played": "lots"}},
                }
            ),
            encoding="utf-8",
        )
        store.load()
        self.assertEqual(store.mode, SOLO)
        self.assertEqual(store.level, "medium")
        self.assertEqual(store.human, WHITE)
        self.assertEqual(store.moves, [])
        self.assertEqual(store.record_for("easy")["played"], 0)

    def test_a_file_that_is_not_an_object_is_ignored(self):
        store = fresh()
        store.path.parent.mkdir(parents=True, exist_ok=True)
        store.path.write_text("[1, 2, 3]", encoding="utf-8")
        store.load()
        self.assertEqual(store.moves, [])


class TestTheRecord(unittest.TestCase):
    def test_only_the_computers_games_are_recorded(self):
        store = fresh()
        store.begin(mode=HOTSEAT, level="medium", human=WHITE)
        store.record(WON, 6)
        self.assertEqual(store.record_for("medium")["played"], 0)

    def test_a_win_keeps_the_best_margin(self):
        store = fresh()
        store.begin(mode=SOLO, level="hard", human=WHITE)
        store.record(WON, 4)
        self.assertEqual(store.record_for("hard")["best"], 4)
        store.record(WON, 7)
        self.assertEqual(store.record_for("hard")["best"], 7)
        store.record(WON, 3)
        self.assertEqual(store.record_for("hard")["best"], 7)

    def test_recording_marks_the_game_as_counted(self):
        store = fresh()
        store.begin(mode=SOLO, level="easy", human=WHITE)
        self.assertFalse(store.recorded)
        store.record(DRAWN)
        self.assertTrue(store.recorded)
        store.begin(mode=SOLO, level="easy", human=WHITE)
        self.assertFalse(store.recorded)

    def test_the_levels_are_counted_apart(self):
        store = fresh()
        store.begin(mode=SOLO, level="easy", human=WHITE)
        store.record(WON, 5)
        store.begin(mode=SOLO, level="hard", human=WHITE)
        store.record(LOST)
        self.assertEqual(store.record_for("easy")[WON], 1)
        self.assertEqual(store.record_for("hard")[LOST], 1)

    def test_a_result_that_is_not_one_is_ignored(self):
        store = fresh()
        store.begin(mode=SOLO, level="easy", human=WHITE)
        store.record("abandoned")
        self.assertEqual(store.record_for("easy")["played"], 0)

    def test_totals_add_the_levels_up(self):
        store = fresh()
        store.begin(mode=SOLO, level="easy", human=WHITE)
        for _ in range(3):
            store.record(WON, 5)
        store.level = "hard"
        store.record(LOST)
        totals = store.totals()
        self.assertEqual(totals["played"], 4)
        self.assertEqual(totals[WON], 3)
        self.assertEqual(totals["best"], 5)


if __name__ == "__main__":
    unittest.main()
