"""The window, driven by calling it rather than by tapping it.

The same approach Keep, Reversi and Chess take: build the real widgets on a real
display and call the methods the buttons call. What is different here is that
the interaction itself is worth testing rather than only its effects -- "a tap
moves the card when there is one place for it to go and asks when there is more
than one" is a rule, and a rule can be wrong.

The layout is tested as arithmetic rather than through a widget, because
`layout_for` and `card_at` take a width and a height as arguments and give back
rectangles. That is deliberate: where a card is drawn and where a tap lands are
the same function, and a bug in it is a game that plays the wrong card. They
live in `layout.py`, which imports no GTK, so those tests run in the build
chroot alongside the rules -- the first cut reached into `widgets.py` for them
and made this whole module unimportable without a display, which is how the
package build found it.

Animations are turned off for the whole module. That is not only for speed: it
is the reduced-motion path, and it is the one where a move has to land and
settle in a single turn of the main loop rather than over a tick callback.

Needs a display. Skipped where there is none, so `python3 -m unittest` on a
machine without GTK still runs the rules and the file.
"""

from __future__ import annotations

import os
import random
import sys
import time
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

HERE = Path(__file__).resolve().parent.parent
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "shared")]

REASON = ""
try:
    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, GLib, Gtk

    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        REASON = "no display"
    elif not Gtk.init_check():
        REASON = "GTK could not open the display"
except (ImportError, ValueError) as exc:  # pragma: no cover - depends on host
    REASON = f"no GTK: {exc}"

if not REASON:
    Adw.init()
    settings = Gtk.Settings.get_default()
    if settings is not None:
        settings.props.gtk_enable_animations = False
    from moarchy_solitaire.newgame import NewGameDialog
    from moarchy_solitaire.window import RecordPage, SolitaireWindow

from moarchy_solitaire.klondike import (  # noqa: E402
    ACE,
    COLUMNS,
    DECK,
    KING,
    STOCK,
    SUITS,
    TABLEAU,
    WASTE,
    Game,
    Move,
    Table,
    deal,
    shuffled,
)
from moarchy_solitaire.layout import card_at, layout_for  # noqa: E402
from moarchy_solitaire.store import LOST, WON, Store  # noqa: E402


def pump(until=None, seconds: float = 6.0) -> bool:
    """Run the main loop until something has happened, or give up."""
    context = GLib.MainContext.default()
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        while context.pending():
            context.iteration(False)
        if until is None or until():
            return True
        time.sleep(0.01)
    return until is None or until()


def card(r: int, s: int) -> int:
    return r * SUITS + s


def bare(**changes) -> Table:
    """An empty table to put exactly what a test needs on."""
    table = deal(tuple(range(DECK)))._with(
        stock=(), waste=(), piles=((),) * COLUMNS, down=(0,) * COLUMNS
    )
    return table._with(**changes)


class TheLayout(unittest.TestCase):
    """Where a card is drawn is where a tap on it lands. One function, tested
    as arithmetic, because a widget is not needed to answer it and a phone is
    not needed to get it wrong."""

    def test_seven_columns_fit_across_a_phone(self):
        table = deal(shuffled(random.Random(1)))
        layout = layout_for(360, 640, table)
        self.assertGreater(layout.card_w, 40)
        right = layout.slot_x(COLUMNS - 1) + layout.card_w
        self.assertLessEqual(right, 360)
        self.assertGreaterEqual(layout.left, 0)

    def test_the_top_row_and_the_tableau_do_not_touch(self):
        table = deal(shuffled(random.Random(2)))
        layout = layout_for(360, 640, table)
        self.assertGreater(layout.tableau_y, layout.top + layout.card_h)

    def test_the_waste_fans_into_the_slot_that_is_left_empty(self):
        table = bare(waste=(1, 2, 3))._with(draw=3)
        layout = layout_for(360, 640, table)
        first = card_at(layout, table, WASTE, 0)
        last = card_at(layout, table, WASTE, 2)
        self.assertGreater(last[0], first[0])
        # ...and stops before the first foundation, which is the whole reason
        # the third slot across is empty.
        self.assertLess(last[0] + last[2], layout.slot_x(3))

    def test_a_face_down_card_shows_less_than_a_face_up_one(self):
        table = deal(shuffled(random.Random(3)))
        layout = layout_for(360, 640, table)
        self.assertLess(layout.down_step, layout.up_step)

    def test_the_tallest_column_a_game_can_have_still_fits(self):
        # Six face down and thirteen face up is as deep as Klondike goes.
        column = tuple(range(19))
        table = bare(piles=(column,) + ((),) * 6, down=(6,) + (0,) * 6)
        layout = layout_for(360, 612, table)
        _, y, _, h = card_at(layout, table, TABLEAU, 18)
        self.assertLessEqual(y + h, 612)


@unittest.skipIf(REASON, REASON)
class WindowBase(unittest.TestCase):
    def setUp(self):
        self.dir = TemporaryDirectory()
        self.store = Store(Path(self.dir.name) / "solitaire.json")
        self.store.begin(draw=1, deck=shuffled(random.Random(5)))

    def open(self) -> SolitaireWindow:
        self.window = SolitaireWindow(self.store)
        self.addCleanup(self.window.destroy)
        return self.window

    def settle(self, window) -> None:
        pump(lambda: not window._table.busy and not window._queue, seconds=3)

    def tearDown(self):
        pump(seconds=0.05)
        self.dir.cleanup()


class TheTable(WindowBase):
    def test_a_new_deal_opens_on_the_deal(self):
        window = self.open()
        self.assertEqual(window.game.table, window.game.start)
        self.assertEqual(window.game.count, 0)

    def test_a_saved_game_is_picked_back_up(self):
        game = Game(self.store.deck, 1)
        game.play(Move(STOCK, WASTE, 1))
        self.store.remember(game)
        window = self.open()
        self.assertEqual(window.game.table, game.table)

    def test_the_table_describes_itself_for_a_screen_reader(self):
        window = self.open()
        text = window._table.describe()
        self.assertIn("face down", text)
        self.assertIn("stock", text)


class OneTap(WindowBase):
    def test_tapping_the_stock_turns_cards_over(self):
        window = self.open()
        window._on_tap(window._table, STOCK, 0)
        self.settle(window)
        self.assertEqual(len(window.game.table.waste), 1)

    def test_tapping_an_empty_stock_turns_the_waste_back(self):
        game = Game(self.store.deck, 1)
        for _ in range(24):
            game.play(Move(STOCK, WASTE, 1))
        self.store.remember(game)
        window = self.open()
        self.assertEqual(len(window.game.table.stock), 0)
        window._on_tap(window._table, STOCK, 0)
        self.settle(window)
        self.assertEqual(len(window.game.table.stock), 24)
        self.assertEqual(len(window.game.table.waste), 0)

    def test_one_destination_moves_the_card_without_asking(self):
        self.store.remember(Game(self.store.deck, 1))
        window = self.open()
        window.game.table = bare(
            piles=((card(ACE, 3),),) + ((),) * 6,
        )
        window._on_tap(window._table, TABLEAU, 0)
        self.settle(window)
        self.assertEqual(window.game.table.up[3], 1)

    def test_more_than_one_destination_picks_the_run_up_and_asks(self):
        window = self.open()
        # A red six with two black sevens to choose between.
        window.game.table = bare(
            piles=(
                (card(6, 0),),
                (card(6, 3),),
                (card(5, 1),),
            )
            + ((),) * 4,
        )
        window._on_tap(window._table, TABLEAU + 2, 0)
        self.assertEqual(window._selected, (TABLEAU + 2, 0))
        self.assertEqual(set(window._drops), {TABLEAU, TABLEAU + 1})
        self.assertEqual(window.game.count, 0)

    def test_tapping_a_destination_plays_the_move(self):
        window = self.open()
        window.game.table = bare(
            piles=((card(6, 0),), (card(6, 3),), (card(5, 1),)) + ((),) * 4,
        )
        window._on_tap(window._table, TABLEAU + 2, 0)
        window._on_tap(window._table, TABLEAU + 1, 0)
        self.settle(window)
        self.assertEqual(
            window.game.table.column(TABLEAU + 1), (card(6, 3), card(5, 1))
        )
        self.assertIsNone(window._selected)

    def test_tapping_the_run_again_puts_it_back_down(self):
        window = self.open()
        window.game.table = bare(
            piles=((card(6, 0),), (card(6, 3),), (card(5, 1),)) + ((),) * 4,
        )
        window._on_tap(window._table, TABLEAU + 2, 0)
        self.assertIsNotNone(window._selected)
        window._on_tap(window._table, TABLEAU + 2, 0)
        self.assertIsNone(window._selected)
        self.assertEqual(window.game.count, 0)

    def test_a_card_with_nowhere_to_go_is_a_silent_miss(self):
        window = self.open()
        window.game.table = bare(piles=((card(5, 0),),) + ((),) * 6)
        window._on_tap(window._table, TABLEAU, 0)
        self.assertIsNone(window._selected)
        self.assertEqual(window.game.count, 0)

    def test_a_face_down_card_is_not_picked_up(self):
        window = self.open()
        window._on_tap(window._table, TABLEAU + 6, 0)
        self.assertIsNone(window._selected)
        self.assertEqual(window.game.count, 0)


class TheBanner(WindowBase):
    def test_it_says_nothing_about_a_fresh_deal(self):
        window = self.open()
        self.assertFalse(window._banner.get_revealed())

    def test_it_offers_to_finish_a_table_with_nothing_face_down(self):
        window = self.open()
        window.game.table = _laid_out()
        window.refresh()
        self.assertTrue(window._banner.get_revealed())
        self.assertEqual(window._banner.get_button_label(), "Send them home")

    def test_it_says_when_a_deal_has_nothing_left_in_it(self):
        window = self.open()
        # Seven columns of two black cards, the lower one face down. Nothing
        # builds on anything, there is no stock to turn over, and there is
        # something still hidden -- which is what a lost Klondike looks like.
        window.game.table = bare(
            piles=tuple(
                (card(r, 0), card(r, 3 if index % 2 else 0))
                for index, r in enumerate((KING, KING - 1, 10, 9, 8, 7, 6))
            ),
            down=(1,) * COLUMNS,
        )
        window.refresh()
        self.assertTrue(window._banner.get_revealed())
        self.assertIn("No moves left", window._banner.get_title())

    def test_it_says_so_when_every_card_is_home(self):
        window = self.open()
        window.game.table = bare(up=(13,) * SUITS)
        window.refresh()
        self.assertIn("Every card home", window._banner.get_title())


class SendingThemHome(WindowBase):
    def test_it_plays_the_table_out_and_wins(self):
        window = self.open()
        window.game.table = _laid_out()
        window.refresh()
        window.send_home()
        pump(lambda: window.game.won and not window._queue, seconds=8)
        self.assertTrue(window.game.won)
        self.assertEqual(self.store.record_for(1)[WON], 1)

    def test_every_move_it_makes_goes_into_the_move_list(self):
        window = self.open()
        window.game.table = _laid_out()
        window.game.start = _laid_out()
        window.refresh()
        window.send_home()
        pump(lambda: window.game.won and not window._queue, seconds=8)
        self.assertEqual(window.game.count, DECK)

    def test_a_tap_during_it_plays_the_rest_at_once(self):
        window = self.open()
        window.game.table = _laid_out()
        window.refresh()
        window.send_home()
        pump(seconds=0.05)
        window._on_tap(window._table, STOCK, 0)
        self.assertEqual(window._queue, [])
        self.assertTrue(window.game.won)


class TheRecord(WindowBase):
    def test_a_win_is_counted_once(self):
        window = self.open()
        window.game.table = bare(up=(13, 13, 13, 12), piles=((51,),) + ((),) * 6)
        window._on_tap(window._table, TABLEAU, 0)
        pump(lambda: self.store.record_for(1)[WON] == 1, seconds=3)
        window._on_settled()
        self.assertEqual(self.store.record_for(1)["played"], 1)

    def test_a_deal_walked_away_from_counts_as_a_loss(self):
        window = self.open()
        window._on_tap(window._table, STOCK, 0)
        self.settle(window)
        window._on_chosen(None, 1)
        entry = self.store.record_for(1)
        self.assertEqual((entry["played"], entry[WON]), (1, 0))

    def test_a_deal_replaced_without_being_played_counts_as_nothing(self):
        window = self.open()
        window._on_chosen(None, 1)
        self.assertEqual(self.store.record_for(1)["played"], 0)

    def test_dealing_the_same_pack_again_keeps_the_pack(self):
        window = self.open()
        deck = window.game.deck
        window._on_tap(window._table, STOCK, 0)
        self.settle(window)
        window.deal_again()
        self.assertEqual(window.game.deck, deck)
        self.assertEqual(window.game.count, 0)
        entry = self.store.record_for(1)
        self.assertEqual((entry["played"], entry[WON]), (1, 0))


class TheButtons(WindowBase):
    def test_undo_is_dead_until_something_has_been_done(self):
        window = self.open()
        self.assertFalse(window._undo.get_sensitive())
        window._on_tap(window._table, STOCK, 0)
        self.settle(window)
        self.assertTrue(window._undo.get_sensitive())

    def test_undo_takes_back_one_move(self):
        window = self.open()
        window._on_tap(window._table, STOCK, 0)
        self.settle(window)
        window.undo()
        self.assertEqual(window.game.count, 0)
        self.assertEqual(window.game.table, window.game.start)

    def test_undo_on_a_fresh_deal_does_nothing(self):
        window = self.open()
        window.undo()
        self.assertEqual(window.game.count, 0)


class TheOtherScreens(WindowBase):
    def test_the_record_builds_with_nothing_in_it(self):
        RecordPage(self.store)

    def test_the_record_builds_with_a_record(self):
        self.store.record(WON, 155)
        self.store.begin(draw=3)
        self.store.record(LOST)
        RecordPage(self.store)

    def test_the_window_can_push_it(self):
        window = self.open()
        window.show_record()
        pump(seconds=0.2)

    def test_the_new_deal_sheet_builds_and_answers(self):
        chosen = []
        window = self.open()
        dialog = NewGameDialog(draw=3, in_progress=True)
        dialog.connect("chosen", lambda _d, *args: chosen.append(args))
        # Presented before Deal is pressed, because closing a dialog that was
        # never presented is a libadwaita critical.
        dialog.present(window)
        pump(seconds=0.2)
        dialog._on_start()
        self.assertEqual(chosen, [(3,)])


def _laid_out() -> Table:
    """The whole deck as four legal runs, which is a table already won."""
    runs = []
    for high, low in ((3, 2), (2, 3), (0, 1), (1, 0)):
        runs.append(
            tuple(
                card(r, high if index % 2 == 0 else low)
                for index, r in enumerate(range(KING, -1, -1))
            )
        )
    return Table(
        stock=(),
        waste=(),
        up=(0,) * SUITS,
        piles=tuple(runs) + ((),) * 3,
        down=(0,) * COLUMNS,
        draw=1,
    )


if __name__ == "__main__":
    unittest.main()
