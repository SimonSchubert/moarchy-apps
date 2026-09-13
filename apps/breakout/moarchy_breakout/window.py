"""The window: a field, a score, and the only frame loop in this repository.

Everything else here is a game of turns, where nothing moves unless somebody
taps. This one runs, and three things follow from that.

**The loop stops when the window does.** A game that kept stepping while the
phone was in a pocket would be a game that lost three lives in a trouser leg,
and a tick callback that kept firing would be sixty wakeups a second for a
window nobody is looking at -- which on a phone is a battery reading somebody
will blame on the wrong app. So the loop is installed when this becomes the
active window and removed the moment it stops being, and the status line says
"Paused" rather than leaving somebody to wonder.

**A frame is capped.** The time between two frames is whatever the compositor
says it is, and after a phone wakes up it can say two seconds -- so the step is
clamped, and the world cuts whatever it is given into slices small enough that
the ball cannot pass through a brick. A physics engine that trusts its clock is
a physics engine that teleports.

**The bat follows a finger absolutely, from anywhere on the field.** Not a drag
from on top of the bat, which is the desktop gesture: a thumb covers a 66px bat
completely, so the only playable arrangement is one where the thumb is somewhere
else -- lower down, out of the way -- and the bat goes where it points. The same
press serves the ball, because a tap and the first frame of a drag are the same
gesture on a touch screen.
"""

from __future__ import annotations

import os
import random
import time

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402
from moarchy_ui.icons import icon  # noqa: E402

from .breakout import (  # noqa: E402
    CLEARED,
    LIVES,
    LOST_BALL,
    WIDTH,
    World,
)
from .store import Store, level_count, level_name  # noqa: E402
from .widgets import FieldView, Lives  # noqa: E402

APP_ICON = "org.moarchy.Breakout"

# The longest step the world is ever given, whatever the frame clock says. A
# fifth of a second is three frames of stutter; past that the honest thing is to
# drop the time rather than to fast-forward a rally nobody saw.
LONGEST_FRAME = 0.05

# How often a rally is written to disk at most. Bricks fall a few a second in a
# good one, and an fsync per brick is an fsync per brick.
SAVE_EVERY = 1.5

# How far an arrow key moves the bat. For the desktop, where there is no finger.
NUDGE = 0.06


class BreakoutWindow(Adw.ApplicationWindow):
    __gtype_name__ = "BreakoutWindow"

    def __init__(self, store: Store, **kwargs) -> None:
        super().__init__(**kwargs)
        self.store = store
        self.rng = random.Random()
        self.world: World = store.world(self.rng)
        self._tick = 0
        self._last = 0
        self._saved = 0.0
        self._dirty = False
        self._recorded = False
        # Held still for a photograph, and for nothing else. A rally is a thing
        # that moves; a rally photographed two and a half seconds after it was
        # set up is a different rally, and usually one where the ball has gone
        # past a bat nobody was holding.
        self._frozen = False

        self.set_title("Breakout")
        self.set_default_size(360, 720)

        self._nav = Adw.NavigationView()
        self._nav.add(self._game_page())
        self.set_content(self._nav)

        for name, handler in (
            ("new", lambda *_: self.new_game()),
            ("stats", lambda *_: self.show_record()),
        ):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", handler)
            self.add_action(action)

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self._on_key)
        self.add_controller(keys)

        self.connect("close-request", self._on_close)
        self.connect("notify::is-active", lambda *_: self._sync_loop())
        self.refresh()
        self._open_requested()

    # --- the page --------------------------------------------------------

    def _game_page(self) -> Adw.NavigationPage:
        header = Adw.HeaderBar()
        self._title = Adw.WindowTitle(title="Breakout", subtitle="")
        header.set_title_widget(self._title)

        menu = Gtk.MenuButton(
            icon_name=icon("open-menu-symbolic", "view-more-symbolic")
        )
        menu.set_tooltip_text("Menu")
        menu.update_property([Gtk.AccessibleProperty.LABEL], ["Menu"])
        model = Gio.Menu()
        model.append("New game", "win.new")
        model.append("Record", "win.stats")
        model.append("About Breakout", "app.about")
        menu.set_menu_model(model)
        header.pack_end(menu)

        self._score = Gtk.Label()
        self._score.add_css_class("reading")
        self._best = Gtk.Label()
        self._best.add_css_class("reading-label")
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        left.set_valign(Gtk.Align.CENTER)
        left.set_halign(Gtk.Align.START)
        left.append(self._score)
        left.append(self._best)

        self._lives = Lives(LIVES)
        self._lives.set_halign(Gtk.Align.END)

        readings = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        readings.set_margin_start(18)
        readings.set_margin_end(18)
        readings.set_margin_top(4)
        readings.append(left)
        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        readings.append(spacer)
        readings.append(self._lives)

        self._field = FieldView()
        self._field.set_margin_start(14)
        self._field.set_margin_end(14)
        self._field.set_margin_top(6)
        self._field.connect("aimed", self._on_aimed)
        self._field.connect("launched", lambda *_: self.serve())

        self._status = Gtk.Label()
        self._status.add_css_class("status")
        self._status.set_margin_top(4)
        self._status.set_margin_bottom(6)
        self._status.set_ellipsize(3)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        body.set_vexpand(True)
        body.set_valign(Gtk.Align.CENTER)
        body.append(readings)
        body.append(self._field)
        body.append(self._status)

        self._toasts = Adw.ToastOverlay()
        self._toasts.set_child(body)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(self._toasts)
        return Adw.NavigationPage.new(view, "Breakout")

    def set_palette(self, palette) -> None:
        """The theme changed. The readings repaint themselves from the reloaded
        stylesheet; the field is drawn by hand and has to be told."""
        self._field.set_colours(palette)

    # --- drawing the state -----------------------------------------------

    def refresh(self) -> None:
        self._field.show(self.world)
        self._score.set_text(str(self.world.score))
        best = self.store.stats["best"]
        self._best.set_text(f"BEST {best}" if best else "SCORE")
        self._lives.refresh(self.world.lives)
        self._title.set_subtitle(
            f"Level {self.store.level + 1} · {level_name(self.store.level)}"
        )
        self._status.set_text(self._status_text())
        if self.world.dead:
            self._status.add_css_class("alert")
        else:
            self._status.remove_css_class("alert")
        self._sync_loop()

    def _status_text(self) -> str:
        if self.world.dead:
            return f"Game over — {self.world.score} points"
        if not self.is_active():
            return "Paused"
        if not self.world.served:
            return "Slide anywhere to aim"
        return f"{self.world.standing} bricks left"

    # --- the loop --------------------------------------------------------

    @property
    def _running(self) -> bool:
        return not self.world.dead and self.is_active() and not self._frozen

    def _sync_loop(self) -> None:
        """Start or stop the frame loop, whichever the window now wants."""
        if self._running and not self._tick:
            self._last = 0
            self._tick = self._field.add_tick_callback(self._frame)
        elif not self._running and self._tick:
            self._field.remove_tick_callback(self._tick)
            self._tick = 0
            self._flush()
        if not self._tick:
            self._status.set_text(self._status_text())

    def _frame(self, _widget, clock) -> bool:
        if not self._running:
            self._tick = 0
            self._flush()
            return GLib.SOURCE_REMOVE
        now = clock.get_frame_time()
        if not self._last:
            self._last = now
        seconds = min((now - self._last) / 1_000_000.0, LONGEST_FRAME)
        self._last = now
        bounce = self.world.advance(seconds)
        self._field.queue_draw()
        if bounce:
            self._react(bounce)
        return GLib.SOURCE_CONTINUE

    def _react(self, bounce) -> None:
        if bounce.broken:
            self._score.set_text(str(self.world.score))
            self._dirty = True
            self._maybe_save()
        if CLEARED in bounce.events:
            self.world = self.store.advance(self.world)
            self._flush()
            self.refresh()
            self._toast(
                f"Level {self.store.level + 1} of {level_count()}"
                f" · {level_name(self.store.level)}"
            )
            return
        if LOST_BALL in bounce.events:
            self.store.remember(self.world)
            self._dirty = True
            self._flush()
            self.refresh()
            if self.world.dead:
                self._finish()

    # --- the person ------------------------------------------------------

    def _on_aimed(self, _field, x: float) -> None:
        if self.world.dead:
            return
        self.world.aim(min(max(x, 0.0), WIDTH))
        self._field.queue_draw()

    def serve(self) -> None:
        if self.world.dead:
            return
        if self.world.serve():
            self._status.set_text(self._status_text())

    def _on_key(self, _controller, keyval: int, _code: int, state) -> bool:
        if state & Gdk.ModifierType.CONTROL_MASK or self.world.dead:
            return False
        if keyval in (Gdk.KEY_Left, Gdk.KEY_a):
            self._on_aimed(None, self.world.bat - NUDGE)
            return True
        if keyval in (Gdk.KEY_Right, Gdk.KEY_d):
            self._on_aimed(None, self.world.bat + NUDGE)
            return True
        if keyval in (Gdk.KEY_space, Gdk.KEY_Return):
            self.serve()
            return True
        return False

    # --- finishing -------------------------------------------------------

    def _finish(self) -> None:
        """Record the game once, and say what it was."""
        if self._recorded:
            return
        self._recorded = True
        best = self.store.stats["best"]
        self.store.record(self.world)
        self._flush()
        self.refresh()
        if self.world.score > best:
            self._toast(f"{self.world.score} — a best")
        else:
            self._toast(f"{self.world.score} points. Tap the menu for another.")

    # --- the rest --------------------------------------------------------

    def new_game(self) -> None:
        if not self.world.dead and self.world.score:
            # A game given up is still a game played, and a high score table
            # that only counted the ones somebody saw out would be a table of
            # the games that were going well.
            self.store.record(self.world)
        self.world = self.store.begin(self.rng)
        self._recorded = False
        self._flush()
        self.refresh()

    def show_record(self) -> None:
        self._nav.push(RecordPage(self.store))

    def _maybe_save(self) -> None:
        now = time.monotonic()
        if now - self._saved >= SAVE_EVERY:
            self.store.remember(self.world)
            self._flush()

    def _flush(self) -> None:
        if not self._dirty and self._saved:
            return
        self.store.remember(self.world)
        self._saved = time.monotonic()
        self._dirty = False
        try:
            self.store.save()
        except OSError as exc:
            self._toast(f"Could not save: {exc.strerror or exc}")

    def _toast(self, text: str) -> None:
        toast = Adw.Toast.new(text)
        toast.set_timeout(3)
        self._toasts.add_toast(toast)

    def _open_requested(self) -> None:
        """Start on a particular screen, for the screenshot harness."""
        if os.environ.get("MOARCHY_BREAKOUT_PAGE") == "record":
            self.show_record()
        if os.environ.get("MOARCHY_BREAKOUT_SERVED"):
            # A ball in flight, for a picture. Aimed slightly off centre so the
            # shot is a rally rather than a ball going straight up, and then
            # frozen -- see `_frozen`.
            self.world.aim(WIDTH * 0.42)
            self.world.waiting = 0.0
            self.serve()
            self.world.advance(0.5)
            self._frozen = True
            self.refresh()

    def _on_close(self, *_args) -> bool:
        self._dirty = True
        self._flush()
        return False


class RecordPage(Adw.NavigationPage):
    """Games played, the best score, and how far the wall has gone.

    Three numbers and no more. This is an arcade game: the only things anybody
    has ever wanted to know about one are what they scored and how far they got.
    """

    __gtype_name__ = "BreakoutRecord"

    def __init__(self, store: Store) -> None:
        super().__init__()
        self.set_title("Record")

        header = Adw.HeaderBar()

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        body.set_margin_top(16)
        body.set_margin_bottom(24)
        body.set_margin_start(14)
        body.set_margin_end(14)

        stats = store.stats
        body.append(
            _tally(
                ("Played", stats["played"]),
                ("Best", stats["best"]),
                ("Furthest", f"{stats['furthest']}/{level_count()}"),
            )
        )

        heading = Gtk.Label(label="WALLS", xalign=0.0)
        heading.add_css_class("section-heading")
        body.append(heading)

        rows = Gtk.ListBox()
        rows.set_selection_mode(Gtk.SelectionMode.NONE)
        rows.add_css_class("boxed-list")
        for number in range(level_count()):
            row = Adw.ActionRow(title=f"{number + 1}. {level_name(number)}")
            reached = stats["furthest"] > number
            row.set_subtitle("Reached" if reached else "Not reached yet")
            if reached:
                row.add_suffix(Gtk.Image.new_from_icon_name("object-select-symbolic"))
            rows.append(row)
        body.append(rows)

        note = Gtk.Label(
            label=(
                "Past the last wall it starts again, faster. The game gets "
                "harder because the ball does, not because somebody wrote a "
                "hundred walls."
            ),
            xalign=0.0,
            wrap=True,
        )
        note.add_css_class("status")
        body.append(note)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        scroller.set_child(body)

        view = Adw.ToolbarView()
        view.add_top_bar(header)
        view.set_content(scroller)
        self.set_child(view)


def _tally(*figures: tuple[str, object]) -> Gtk.Widget:
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.add_css_class("tally")
    box.set_homogeneous(True)
    for label, value in figures:
        column = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        figure = Gtk.Label(label=str(value))
        figure.add_css_class("figure")
        column.append(figure)
        caption = Gtk.Label(label=label.upper())
        caption.add_css_class("figure-label")
        column.append(caption)
        box.append(column)
    return box
