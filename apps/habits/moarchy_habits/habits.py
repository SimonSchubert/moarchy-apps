"""The habits themselves, and the one file they live in.

No database, for the same reason Keep has none: a person tracks a dozen habits,
not a million rows, and a single JSON file can be read by anything, diffed,
synced with rsync or git, and repaired by hand. `sqlite3 habits.db .dump` is not
a thing you can do on a device with no keyboard.

Nothing in this module imports GTK. That is deliberate -- the storage layer and
every date calculation in it can be tested on any machine with a Python, while
the UI needs the whole GNOME stack. In practice that is the difference between a
test suite that runs and one that does not.

Writes go through a temporary file, an fsync and a rename. On a phone, "the
process was killed while saving" is the ordinary case rather than the strange
one: the compositor kills backgrounded apps under memory pressure and the
battery is the only power supply. rename(2) is atomic on ext4, so a tick that
was saved stays saved, and an interrupted save leaves the previous file whole.

A tick is stored against a *date*, never a timestamp. The question a habit
tracker answers is "did I do it today", and today is a calendar day in the
user's own timezone -- storing UTC instants would move a 23:30 tick into
tomorrow for half the world.
"""

from __future__ import annotations

import json
import os
import time
import uuid
from dataclasses import dataclass, field
from datetime import date, timedelta
from pathlib import Path

SCHEMA = 1

BOOLEAN = "boolean"
MEASURABLE = "measurable"

# How much history the strength score remembers. Thirty days of doing a habit
# puts the score near the top; thirty days of not doing it puts it near the
# bottom. Short enough that a bad fortnight shows, long enough that one missed
# Tuesday does not read as failure.
HALF_LIFE_DAYS = 30.0

# The streaks worth saying something about. A week is the first one that feels
# earned, a month is the one the strength score is scaled to, and the other two
# are far enough apart that crossing one stays rare. Deliberately short: a list
# of twenty milestones is a list of twenty non-events.
MILESTONES = (7, 30, 100, 365)

# Days shown across a phone row. Five 44px targets plus gaps is what fits beside
# a readable habit name at 360px, and 44px is the smallest thing a thumb hits
# reliably.
STRIP_DAYS = 5

# The longest trailing window a frequency may be expressed over. Guards the
# rolling-window scan below from a malformed file asking for ten years of
# lookback on every repaint.
MAX_PERIOD = 31


def data_dir() -> Path:
    """Where habits live. Overridable, which is what makes the tests and the
    screenshot harness possible without touching the real ones."""
    override = os.environ.get("MOARCHY_HABITS_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-habits"


def today() -> date:
    """Overridable today, so a test does not depend on the day it runs."""
    stamp = os.environ.get("MOARCHY_HABITS_TODAY")
    if stamp:
        try:
            return date.fromisoformat(stamp)
        except ValueError:
            pass
    return date.today()


def _iso(day: date) -> str:
    return day.isoformat()


def _number(value, fallback: float) -> float:
    return (
        float(value)
        if isinstance(value, (int, float)) and not isinstance(value, bool)
        else fallback
    )


@dataclass
class Habit:
    """One habit, and every day it was recorded.

    `entries` maps an ISO date to a number. For a boolean habit that number is
    1; for a measurable one it is the amount done, and the habit counts as kept
    on a day when the amount reaches `target`. Storing a number either way means
    a boolean habit can be turned into a measurable one without a migration.
    """

    id: str = field(default_factory=lambda: uuid.uuid4().hex)
    name: str = ""
    question: str = ""
    kind: str = BOOLEAN
    target: float = 1.0
    unit: str = ""
    colour: str = "green"
    # "n times per d days". 1/1 is daily, 3/7 is three times a week.
    freq_num: int = 1
    freq_den: int = 1
    created: float = field(default_factory=time.time)
    archived: bool = False
    entries: dict[str, float] = field(default_factory=dict)

    # --- the day ---------------------------------------------------------

    def value(self, day: date) -> float:
        return self.entries.get(_iso(day), 0.0)

    def kept(self, day: date) -> bool:
        """Was the habit's own bar met on this particular day?"""
        return (
            self.value(day) >= self.target if self.target > 0 else self.value(day) > 0
        )

    def set_value(self, day: date, amount: float) -> None:
        key = _iso(day)
        if amount <= 0:
            self.entries.pop(key, None)
        else:
            self.entries[key] = float(amount)

    def toggle(self, day: date) -> bool:
        """Tick or untick a day. Returns the new state."""
        if self.kept(day):
            self.set_value(day, 0)
            return False
        self.set_value(day, self.target if self.kept_is_target else 1.0)
        return True

    @property
    def kept_is_target(self) -> bool:
        return self.kind == MEASURABLE and self.target > 0

    @property
    def is_daily(self) -> bool:
        return self.freq_num >= self.freq_den

    # --- the rolling window ----------------------------------------------

    def on_track(self, day: date) -> bool:
        """Is the habit meeting its own frequency as of this day?

        A daily habit is on track on a day it was kept. A "three times a week"
        habit is on track on any day where the trailing week already holds three
        kept days -- which is the whole point of saying three times a week
        rather than naming which three.
        """
        if self.is_daily:
            return self.kept(day)
        period = min(max(self.freq_den, 1), MAX_PERIOD)
        need = min(max(self.freq_num, 1), period)
        hit = sum(1 for i in range(period) if self.kept(day - timedelta(days=i)))
        return hit >= need

    def streak(self, upto: date | None = None) -> int:
        """Consecutive on-track days ending today.

        Today is forgiving: a day that has not been kept *yet* does not break a
        streak, because the day is not over. Yesterday is not forgiving.
        """
        day = upto or today()
        if not self.on_track(day):
            day -= timedelta(days=1)
        count = 0
        # A habit older than ten years has bigger problems than a wrong number.
        for _ in range(3660):
            if not self.on_track(day):
                break
            count += 1
            day -= timedelta(days=1)
        return count

    def milestone_crossed(self, before: int, after: int) -> int | None:
        """The milestone a streak just passed, if it passed one.

        Takes both numbers rather than just the new one, because the reward is
        for *crossing*: re-ticking a day inside a 40-day streak must not
        re-announce the 30, and unticking and re-ticking must not either.
        """
        if after <= before:
            return None
        return next((m for m in MILESTONES if before < m <= after), None)

    def next_milestone(self, upto: date | None = None) -> tuple[int, int] | None:
        """The next milestone and how many days away it is, or None past the last."""
        streak = self.streak(upto)
        target = next((m for m in MILESTONES if m > streak), None)
        return None if target is None else (target, target - streak)

    def best_streak(self) -> int:
        """The longest run this habit has ever had."""
        if not self.entries:
            return 0
        try:
            first = min(date.fromisoformat(k) for k in self.entries)
        except ValueError:
            return 0
        best = run = 0
        day, last = first, today()
        while day <= last:
            if self.on_track(day):
                run += 1
                best = max(best, run)
            else:
                run = 0
            day += timedelta(days=1)
        return best

    def score(self, upto: date | None = None) -> float:
        """Strength, 0.0 to 1.0: an exponential moving average of on-track days.

        Loop calls this a habit's strength and it is the number worth showing,
        because a streak is binary and cruel -- it says nothing between "42" and
        "0" -- while this drops a little for a missed day and recovers as fast
        as it fell. Weighted so recent days count for more, with a thirty-day
        half life.
        """
        day = upto or today()
        if not self.entries:
            return 0.0
        try:
            first = min(date.fromisoformat(k) for k in self.entries)
        except ValueError:
            return 0.0
        span = (day - first).days
        if span < 0:
            return 0.0
        decay = 0.5 ** (1.0 / HALF_LIFE_DAYS)
        score = 0.0
        # Walk forward from the first record so early days decay away properly.
        for i in range(span + 1):
            score = score * decay + (1.0 - decay) * (
                1.0 if self.on_track(first + timedelta(days=i)) else 0.0
            )
        # Normalise: a perfect run converges on (1 - decay^n), not on 1.
        ceiling = 1.0 - decay ** (span + 1)
        return min(score / ceiling, 1.0) if ceiling > 0 else 0.0

    def total(self) -> float:
        return sum(self.entries.values())

    def kept_days(self) -> int:
        return sum(1 for k in self.entries if self.kept(date.fromisoformat(k)))

    # --- serialisation ---------------------------------------------------

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "question": self.question,
            "kind": self.kind,
            "target": self.target,
            "unit": self.unit,
            "colour": self.colour,
            "freq_num": self.freq_num,
            "freq_den": self.freq_den,
            "created": self.created,
            "archived": self.archived,
            "entries": self.entries,
        }

    @classmethod
    def from_dict(cls, data: dict) -> Habit:
        if not isinstance(data, dict):
            raise ValueError("habit is not a table")
        entries: dict[str, float] = {}
        raw = data.get("entries")
        if isinstance(raw, dict):
            for key, value in raw.items():
                # A key that is not a date would break every window scan later,
                # where there is no good place to report it. Drop it here.
                if not isinstance(key, str):
                    continue
                try:
                    date.fromisoformat(key)
                except ValueError:
                    continue
                amount = _number(value, 0.0)
                if amount > 0:
                    entries[key] = amount
        kind = data.get("kind")
        target = _number(data.get("target"), 1.0)
        return cls(
            id=str(data.get("id") or uuid.uuid4().hex),
            name=str(data.get("name") or ""),
            question=str(data.get("question") or ""),
            kind=kind if kind in (BOOLEAN, MEASURABLE) else BOOLEAN,
            target=target if target > 0 else 1.0,
            unit=str(data.get("unit") or ""),
            colour=str(data.get("colour") or "green"),
            freq_num=max(int(_number(data.get("freq_num"), 1)), 1),
            freq_den=min(max(int(_number(data.get("freq_den"), 1)), 1), MAX_PERIOD),
            created=_number(data.get("created"), time.time()),
            archived=bool(data.get("archived")),
            entries=entries,
        )


class Store:
    """Every habit, in order, in one file."""

    def __init__(self, path: Path | str | None = None) -> None:
        self.path = Path(path) if path else data_dir() / "habits.json"
        self.habits: list[Habit] = []

    # --- file ------------------------------------------------------------

    def load(self) -> None:
        try:
            raw = self.path.read_text(encoding="utf-8")
        except FileNotFoundError:
            self.habits = []
            return
        except OSError:
            self.habits = []
            return
        try:
            data = json.loads(raw)
            records = data.get("habits", []) if isinstance(data, dict) else []
        except ValueError:
            # A file we cannot parse is moved aside rather than overwritten: the
            # next save would otherwise destroy whatever the user actually had.
            self._rescue()
            self.habits = []
            return
        habits = []
        for record in records:
            try:
                habits.append(Habit.from_dict(record))
            except (ValueError, TypeError):
                continue
        self.habits = habits

    def _rescue(self) -> Path | None:
        spare = self.path.with_suffix(f".broken-{int(time.time())}.json")
        try:
            self.path.rename(spare)
            return spare
        except OSError:
            return None

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"schema": SCHEMA, "habits": [h.to_dict() for h in self.habits]}
        tmp = self.path.with_suffix(".tmp")
        with tmp.open("w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=1)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, self.path)

    # --- collection ------------------------------------------------------

    def active(self) -> list[Habit]:
        return [h for h in self.habits if not h.archived]

    def today_progress(self, day: date | None = None) -> tuple[int, int]:
        """(kept, total) for today.

        Counts every active habit, including ones whose frequency does not
        require them today. A "3x a week" habit still offers a box to tick on a
        Tuesday, so a day where every box is ticked is a real thing to finish --
        and pretending a habit is not there today would make the count move for
        reasons the user cannot see.
        """
        now = day or today()
        habits = self.active()
        return sum(1 for h in habits if h.kept(now)), len(habits)

    def get(self, habit_id: str) -> Habit | None:
        return next((h for h in self.habits if h.id == habit_id), None)

    def create(self, name: str = "", **kwargs) -> Habit:
        habit = Habit(name=name, **kwargs)
        self.habits.append(habit)
        return habit

    def delete(self, habit: Habit) -> int:
        """Remove a habit, returning where it was so it can be put back."""
        try:
            index = self.habits.index(habit)
        except ValueError:
            return -1
        self.habits.pop(index)
        return index

    def restore(self, habit: Habit, index: int) -> None:
        self.habits.insert(max(0, min(index, len(self.habits))), habit)

    def move(self, habit: Habit, to: int) -> None:
        if habit not in self.habits:
            return
        self.habits.remove(habit)
        self.habits.insert(max(0, min(to, len(self.habits))), habit)


def recent_days(count: int = STRIP_DAYS, end: date | None = None) -> list[date]:
    """The days a row shows, oldest first, ending today."""
    last = end or today()
    return [last - timedelta(days=i) for i in range(count - 1, -1, -1)]
