"""What survives the app being killed: the stars, and the last launches seen.

Two files, and the split is the whole design of this module.

`favourites.json` is a list of launch ids and is the only thing in this app a
person has made. It is written the instant a star is tapped, through a
temporary file and a rename, because on a phone "the process was killed a
moment after the tap" is the ordinary case: the compositor reclaims
backgrounded apps, and nothing asks first.

`upcoming.json` is the last answer Launch Library gave. It exists so that an
app opened on a train with no signal opens on countdowns rather than on an
apology, and it is disposable by definition -- every byte of it is replaced
by the next successful fetch. It is written when the window leaves the
screen rather than on each refresh, because a refresh around T-0 is every
two minutes and this file is a hundred kilobytes: an app left open through
a countdown would otherwise fsync several megabytes onto the phone's flash
to save a copy of something it already had in memory.

The launches are cached; *which ones you fly to* is not. Nothing here holds
a ticket, a seat, or a stream URL, and the app never asks for one -- the
whole file is public data plus a list of names, which is what makes leaving
it unencrypted in ~/.local/share an honest decision rather than an oversight.
"""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

from .launches import Launch

SCHEMA = 1

FAVOURITES = "favourites.json"
UPCOMING = "upcoming.json"

# A guard on the file rather than on the person. Nobody stars two hundred
# launches; a favourites file that says they do has been written by something
# other than this app, and the list is what every refresh iterates.
MAX_FAVOURITES = 200


def data_dir() -> Path:
    """Where this app keeps its two files.

    Overridable, which is what makes the tests and the screenshot harness
    possible without touching anybody's real stars.
    """
    override = os.environ.get("MOARCHY_LAUNCHES_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-launches"


def _write(path: Path, payload: dict) -> None:
    """Temporary file, fsync, rename. See the header."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def _read(path: Path) -> dict | None:
    """The file as a table, or None for anything else.

    A file that cannot be parsed is moved aside rather than left in place to
    be overwritten by the next save, which is the one operation that would
    destroy whatever the user actually had. The same thing Habits does, for
    the same reason: the broken copy is the only evidence of what went wrong.
    """
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError:
        return None
    try:
        data = json.loads(raw)
    except ValueError:
        try:
            path.rename(path.with_suffix(f".broken-{int(time.time())}.json"))
        except OSError:
            pass
        return None
    return data if isinstance(data, dict) else None


class Store:
    """The stars, the cached upcoming list, and the two files they live in."""

    def __init__(self, directory: Path | str | None = None) -> None:
        self.dir = Path(directory) if directory else data_dir()
        # Launch ids, in the order they were starred. See `starred()`.
        self.favourites: list[str] = []
        self.launches: list[Launch] = []
        # Wall-clock seconds, because this one is compared against a clock the
        # user can see. Everything about *when to fetch again* is monotonic and
        # lives in the window.
        self.fetched = 0.0

    # --- files -----------------------------------------------------------

    @property
    def favourites_path(self) -> Path:
        return self.dir / FAVOURITES

    @property
    def upcoming_path(self) -> Path:
        return self.dir / UPCOMING

    def load(self) -> None:
        self._load_favourites()
        self._load_upcoming()

    def _load_favourites(self) -> None:
        data = _read(self.favourites_path)
        raw = data.get("favourites") if data else None
        if not isinstance(raw, list):
            self.favourites = []
            return
        seen: list[str] = []
        for entry in raw:
            if isinstance(entry, str) and entry and entry not in seen:
                seen.append(entry)
        self.favourites = seen[:MAX_FAVOURITES]

    def _load_upcoming(self) -> None:
        data = _read(self.upcoming_path)
        if not data:
            return
        records = data.get("launches")
        if not isinstance(records, list):
            return
        launches = []
        for record in records:
            try:
                launches.append(Launch.from_dict(record))
            except (ValueError, TypeError):
                continue
        self.launches = launches
        fetched = data.get("fetched")
        self.fetched = float(fetched) if isinstance(fetched, (int, float)) else 0.0

    def save_favourites(self) -> None:
        _write(self.favourites_path, {"schema": SCHEMA, "favourites": self.favourites})

    def save_upcoming(self) -> None:
        if not self.launches:
            # Nothing to cache, and writing an empty list would turn "we have
            # never fetched" into "the pad is empty" on the next launch.
            return
        _write(
            self.upcoming_path,
            {
                "schema": SCHEMA,
                "fetched": self.fetched,
                "launches": [launch.to_dict() for launch in self.launches],
            },
        )

    # --- the stars -------------------------------------------------------

    def is_favourite(self, launch_id: str) -> bool:
        return launch_id in self.favourites

    def toggle(self, launch_id: str) -> bool:
        """Star or unstar a launch. Returns whether it is now starred.

        Appends rather than inserts, which is what makes the starred page read
        in the order things were added to it.
        """
        if launch_id in self.favourites:
            self.favourites.remove(launch_id)
            return False
        if len(self.favourites) >= MAX_FAVOURITES:
            return False
        self.favourites.append(launch_id)
        return True

    def get(self, launch_id: str) -> Launch | None:
        for launch in self.launches:
            if launch.id == launch_id:
                return launch
        return None

    def starred(self) -> list[Launch]:
        """The starred launches, in the order they were starred.

        Not in NET order, which is the obvious alternative and is wrong on a
        phone: a watchlist sorted by countdown reorders itself under a thumb
        that is halfway down it, and the one ordering a person can actually
        control -- without a drag handle this app has no room for -- is when
        they added each one.

        A star with no launch behind it is left out rather than drawn as a
        row of dashes. That happens when a launch has flown off the upcoming
        list, and a row that says nothing about a launch is worse than the
        launch simply being gone. There is no second request for it: fifteen
        calls an hour cannot afford Coins' "ask by name" exception.
        """
        known = {launch.id: launch for launch in self.launches}
        return [known[i] for i in self.favourites if i in known]

    # --- the list --------------------------------------------------------

    def replace(self, launches: list[Launch], *, fetched: float) -> None:
        """Take a fetch, keeping at most one row per launch, in arrival order.

        Arrival order *is* NET order: that is how the endpoint sorts, and it
        is how the upcoming page is drawn.
        """
        seen: dict[str, Launch] = {}
        order: list[str] = []
        for launch in launches:
            if launch.id not in seen:
                order.append(launch.id)
            seen[launch.id] = launch
        self.launches = [seen[i] for i in order]
        self.fetched = fetched

    def age(self, now: float | None = None) -> float:
        """How old the cached launches are, in seconds, never negative."""
        if self.fetched <= 0:
            return float("inf")
        return max(0.0, (now if now is not None else time.time()) - self.fetched)
