"""Points, levels and achievements.

The reward loop, in one GTK-free file so every rule in it can be tested.

Two things are deliberately true of the scoring below. It only ever counts days
that were actually kept -- there is no way to earn a point by opening the app,
by tapping something, or by waiting -- and nothing is ever taken away. A habit
tracker that can punish you is a habit tracker you avoid opening on the days it
matters most, which is the opposite of the job.

Points are not a currency: there is nothing to spend them on and nothing to buy.
They exist to turn a set of unrelated streaks into one number that goes up, so
that a bad week on one habit does not read as a bad week.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta

from .habits import MILESTONES, Habit, Store, today

# A kept day is worth this much on its own.
BASE_POINTS = 10

# ...plus one per day of the streak it belongs to, capped so that a very long
# streak does not make a new habit feel pointless to start.
STREAK_BONUS_CAP = 10

# Thresholds and what to call someone who has passed them. A single daily habit
# earns 10-20 a day, so the first level is about a week and the last is a year
# of several habits -- far enough apart that arriving is an event.
LEVELS: tuple[tuple[int, str], ...] = (
    (0, "Day one"),
    (100, "Getting going"),
    (300, "Regular"),
    (700, "Committed"),
    (1500, "Steady"),
    (3000, "Ingrained"),
    (6000, "Second nature"),
)


def day_points(habit: Habit, day: date) -> int:
    """What one kept day of one habit is worth."""
    if not habit.kept(day):
        return 0
    return BASE_POINTS + min(habit.streak(day), STREAK_BONUS_CAP)


def habit_points(habit: Habit) -> int:
    """Everything this habit has ever earned."""
    total = 0
    for key in habit.entries:
        try:
            total += day_points(habit, date.fromisoformat(key))
        except ValueError:
            continue
    return total


def total_points(store: Store) -> int:
    return sum(habit_points(h) for h in store.active())


def level_for(points: int) -> tuple[int, str, int, int | None]:
    """(level number from 1, its name, points into it, points still to go).

    The last level has nowhere to go, and says so with None rather than
    inventing a bigger number nobody will reach.
    """
    index = 0
    for i, (threshold, _) in enumerate(LEVELS):
        if points >= threshold:
            index = i
    floor, name = LEVELS[index]
    if index + 1 >= len(LEVELS):
        return index + 1, name, points - floor, None
    ceiling = LEVELS[index + 1][0]
    return index + 1, name, points - floor, ceiling - points


# --- achievements ----------------------------------------------------------
#
# Each is earned once and never lost. The predicates read the store as it is
# now, so an achievement whose condition was met before the app learned to
# record it is still awarded the first time it is checked -- which is why they
# are written as questions about history rather than about the last tap.


def _any_streak(store: Store, length: int) -> bool:
    return any(h.best_streak() >= length for h in store.active())


def _tracked_since(habit: Habit) -> date | None:
    """The first day this habit can fairly be judged on.

    Its creation date normally -- but a habit whose history was imported has
    entries older than the record of its own creation, and judging it from the
    later of the two would throw that history away. The earlier wins.
    """
    days = []
    try:
        days.append(datetime.fromtimestamp(habit.created).date())
    except (OverflowError, OSError, ValueError):
        pass
    for key in habit.entries:
        try:
            days.append(date.fromisoformat(key))
        except ValueError:
            continue
    return min(days) if days else None


def _due_on(store: Store, day: date) -> list[Habit]:
    """The habits that existed on a day, so a day is not judged against habits
    that had not been started yet."""
    out = []
    for habit in store.active():
        since = _tracked_since(habit)
        if since is not None and since <= day:
            out.append(habit)
    return out


# A sweep means sweeping more than one thing. With a single habit it would be
# the same event as "First day", handed out twice under two names.
SWEEP_MINIMUM = 2


def _perfect_days(store: Store) -> int:
    """How many days every habit that existed by then was kept."""
    days: set[str] = set()
    for h in store.active():
        days |= set(h.entries)
    count = 0
    for key in days:
        try:
            day = date.fromisoformat(key)
        except ValueError:
            continue
        due = _due_on(store, day)
        if len(due) >= SWEEP_MINIMUM and all(h.kept(day) for h in due):
            count += 1
    return count


def _perfect_run(store: Store, length: int) -> bool:
    if not store.active():
        return False
    now = today()
    run = 0
    for back in range(400):
        day = now - timedelta(days=back)
        due = _due_on(store, day)
        if len(due) < SWEEP_MINIMUM:
            continue
        if all(h.kept(day) for h in due):
            run += 1
            if run >= length:
                return True
        else:
            run = 0
    return False


def _comeback(store: Store) -> bool:
    """A streak of a week or more, built after a gap of three days or more.

    The one worth rewarding most. Everybody starts; the people who keep a habit
    are the ones who start again.
    """
    for habit in store.active():
        keys = sorted(habit.entries)
        if len(keys) < 2:
            continue
        gap_seen = False
        run = 0
        previous = None
        for key in keys:
            try:
                day = date.fromisoformat(key)
            except ValueError:
                continue
            if previous is not None and (day - previous).days >= 4:
                gap_seen, run = True, 0
            run = run + 1 if previous is None or (day - previous).days == 1 else 1
            if gap_seen and run >= 7:
                return True
            previous = day
    return False


def _total_kept(store: Store) -> int:
    return sum(h.kept_days() for h in store.active())


ACHIEVEMENTS: tuple[tuple[str, str, str], ...] = (
    ("first", "First day", "Keep any habit once"),
    ("week", "A full week", f"Reach a {MILESTONES[0]}-day streak"),
    ("month", "A month", f"Reach a {MILESTONES[1]}-day streak"),
    ("century", "A hundred", f"Reach a {MILESTONES[2]}-day streak"),
    ("year", "A year", f"Reach a {MILESTONES[3]}-day streak"),
    ("perfect", "Clean sweep", "Keep every habit on the same day"),
    ("perfect_week", "Seven clean", "Keep every habit, seven days running"),
    ("comeback", "Back on it", "Build a week-long streak after a lapse"),
    ("handful", "A handful", "Track five habits at once"),
    ("hundred_days", "Hundred days", "Keep habits on a hundred days in total"),
)

_TESTS = {
    "first": lambda s: _total_kept(s) >= 1,
    "week": lambda s: _any_streak(s, MILESTONES[0]),
    "month": lambda s: _any_streak(s, MILESTONES[1]),
    "century": lambda s: _any_streak(s, MILESTONES[2]),
    "year": lambda s: _any_streak(s, MILESTONES[3]),
    "perfect": lambda s: _perfect_days(s) >= 1,
    "perfect_week": lambda s: _perfect_run(s, 7),
    "comeback": _comeback,
    "handful": lambda s: len(s.active()) >= 5,
    "hundred_days": lambda s: _total_kept(s) >= 100,
}

ACHIEVEMENT_KEYS = tuple(key for key, _, _ in ACHIEVEMENTS)


def qualifies(store: Store, key: str) -> bool:
    test = _TESTS.get(key)
    return bool(test and test(store))


def newly_earned(store: Store) -> list[str]:
    """Achievements the store qualifies for and has not been credited with.

    Does not record them -- the caller does that, so that the UI decides when to
    say so and the storage layer stays the only thing that writes.
    """
    return [
        k
        for k in ACHIEVEMENT_KEYS
        if k not in store.achievements and qualifies(store, k)
    ]


def describe(key: str) -> tuple[str, str]:
    for k, name, blurb in ACHIEVEMENTS:
        if k == key:
            return name, blurb
    return key, ""
