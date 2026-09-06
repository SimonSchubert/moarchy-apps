"""The notes themselves, and the one file they live in.

No database. A phone that holds a few hundred notes does not need one, and a
single JSON file is worth more than the indexing it gives up: it can be read by
anything, diffed, synced with rsync or git, and repaired by hand when something
goes wrong. `sqlite3 notes.db .dump` is not a thing you can do on a device with
no keyboard.

Nothing in this module imports GTK. That is deliberate -- it means the storage
layer can be tested on any machine with a Python, while the UI needs the whole
GNOME stack, and in practice that is the difference between a test suite that
runs and one that does not.

Writes go through a temporary file, an fsync, and a rename. On a phone, "the
process was killed while saving" is the ordinary case rather than the strange
one: the compositor kills backgrounded apps under memory pressure, and the
battery is the only power supply. rename(2) is atomic on ext4, so a note that
was saved stays saved, and a save that was interrupted leaves the previous file
untouched rather than half of the new one.
"""

from __future__ import annotations

import json
import os
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

SCHEMA = 1

TEXT = "text"
LIST = "list"

# How many items of a checklist a card shows before it says "+3 more". Keep
# shows a similar handful; the point of the grid is to be scannable, and a
# 40-item shopping list rendered in full is a column of its own.
CARD_ITEMS = 7


def data_dir() -> Path:
    """Where notes live. Overridable, which is what makes tests and the
    screenshot harness possible without touching the real ones."""
    override = os.environ.get("MOARCHY_KEEP_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / "moarchy-keep"


@dataclass
class Item:
    """One line of a checklist."""

    text: str = ""
    done: bool = False

    def to_dict(self) -> dict:
        return {"text": self.text, "done": self.done}

    @classmethod
    def from_dict(cls, data: dict) -> Item:
        return cls(text=str(data.get("text", "")), done=bool(data.get("done", False)))


@dataclass
class Note:
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    kind: str = TEXT
    title: str = ""
    body: str = ""
    items: list[Item] = field(default_factory=list)
    colour: str = "default"
    pinned: bool = False
    created: float = field(default_factory=time.time)
    edited: float = field(default_factory=time.time)

    # --- shape -----------------------------------------------------------

    @property
    def is_list(self) -> bool:
        return self.kind == LIST

    @property
    def is_empty(self) -> bool:
        """A note with nothing in it. Keep discards these on close rather than
        filling the grid with blank cards someone tapped by accident."""
        if self.title.strip():
            return False
        if self.is_list:
            return not any(item.text.strip() for item in self.items)
        return not self.body.strip()

    @property
    def open_items(self) -> list[Item]:
        return [item for item in self.items if not item.done]

    @property
    def done_items(self) -> list[Item]:
        return [item for item in self.items if item.done]

    def touch(self) -> None:
        self.edited = time.time()

    def to_text(self) -> None:
        """Checklist -> prose. Ticked items keep their tick as a character,
        because dropping it would quietly lose the only state they had."""
        if not self.is_list:
            return
        lines = [
            ("✓ " if item.done else "") + item.text
            for item in self.items
            if item.text.strip()
        ]
        self.body = "\n".join(lines)
        self.items = []
        self.kind = TEXT

    def to_list(self) -> None:
        """Prose -> checklist, one line per item, blank lines dropped."""
        if self.is_list:
            return
        self.items = [
            Item(text=line.strip()) for line in self.body.splitlines() if line.strip()
        ]
        self.body = ""
        self.kind = LIST

    def matches(self, query: str) -> bool:
        needle = query.strip().lower()
        if not needle:
            return True
        haystack = [self.title, self.body] + [item.text for item in self.items]
        return any(needle in part.lower() for part in haystack)

    # --- serialisation ---------------------------------------------------

    def to_dict(self) -> dict:
        data = {
            "id": self.id,
            "kind": self.kind,
            "title": self.title,
            "colour": self.colour,
            "pinned": self.pinned,
            "created": round(self.created, 3),
            "edited": round(self.edited, 3),
        }
        # Only the field the note actually uses, so the file stays readable.
        if self.is_list:
            data["items"] = [item.to_dict() for item in self.items]
        else:
            data["body"] = self.body
        return data

    @classmethod
    def from_dict(cls, data: dict) -> Note:
        kind = data.get("kind")
        if kind not in (TEXT, LIST):
            # An unknown kind from a newer version still has a title and
            # probably a body; showing it as text loses less than dropping it.
            kind = LIST if data.get("items") else TEXT
        now = time.time()
        created = _number(data.get("created"), now)
        return cls(
            id=str(data.get("id") or uuid.uuid4().hex[:12]),
            kind=kind,
            title=str(data.get("title", "")),
            body=str(data.get("body", "")),
            items=[
                Item.from_dict(i) for i in data.get("items", []) if isinstance(i, dict)
            ],
            colour=str(data.get("colour", "default")),
            pinned=bool(data.get("pinned", False)),
            created=created,
            edited=_number(data.get("edited"), created),
        )


def _number(value, fallback: float) -> float:
    return float(value) if isinstance(value, (int, float)) else fallback


def edited_label(when: float, now: float | None = None) -> str:
    """ "Edited 14:32" for today, "Edited 3 Sep" for this year, else the year.

    Keep puts this at the bottom of an open note and nowhere else. It answers
    "am I looking at the version I typed on the train" without spending a line
    of a 360px-wide card on a date nobody is scanning for.
    """
    stamp = datetime.fromtimestamp(when)
    today = datetime.fromtimestamp(now if now is not None else time.time())
    if stamp.date() == today.date():
        return f"Edited {stamp:%H:%M}"
    if stamp.year == today.year:
        return f"Edited {stamp.day} {stamp:%b}"
    return f"Edited {stamp.day} {stamp:%b %Y}"


class Store:
    """Every note, and the file they are read from and written to."""

    def __init__(self, path: Path | str | None = None) -> None:
        self.path = Path(path) if path else data_dir() / "notes.json"
        self.notes: list[Note] = []
        self.view = "grid"  # or "list": one column, Keep's other view
        self.rescued: Path | None = None  # set when load() found a broken file

    # --- disk ------------------------------------------------------------

    def load(self) -> None:
        try:
            raw = self.path.read_text(encoding="utf-8")
        except FileNotFoundError:
            return
        except OSError:
            # Unreadable rather than absent -- a permissions or IO problem.
            # Refusing to start would be worse than starting empty, but we must
            # not then save over it, so treat it as rescued.
            self.rescued = self.path
            return

        # Never overwrite a file we could not understand: the next save would
        # destroy whatever it holds. Move it aside, keep the copy, and start
        # clean -- the window says so in a toast that does not time out.
        try:
            data = json.loads(raw)
            notes = data["notes"]
        except (ValueError, KeyError, TypeError):
            self.rescued = self._rescue()
            return
        if not isinstance(notes, list):
            self.rescued = self._rescue()
            return

        self.notes = [Note.from_dict(n) for n in notes if isinstance(n, dict)]
        if data.get("view") in ("grid", "list"):
            self.view = data["view"]

    def _rescue(self) -> Path | None:
        spare = self.path.with_suffix(f".broken-{int(time.time())}.json")
        try:
            os.replace(self.path, spare)
        except OSError:
            return self.path
        return spare

    def save(self) -> None:
        """Temporary file, fsync, rename, fsync the directory.

        The last step is the one that is easy to leave out and hard to notice:
        rename(2) is atomic with respect to a crash, but the *directory entry*
        it creates is still only in the page cache until the directory itself
        is synced. Without it, power loss seconds after a save can leave the
        rename undone -- which on a device whose only power supply is a battery
        is not a theoretical concern.
        """
        if self.rescued is not None:
            # We are holding a file we could not parse. Writing would destroy
            # it; the copy under .broken-*.json is the user's to recover.
            return
        payload = {
            "schema": SCHEMA,
            "view": self.view,
            "notes": [note.to_dict() for note in self.notes],
        }
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=1)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, self.path)
        fd = os.open(self.path.parent, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)

    # --- collection ------------------------------------------------------

    def create(self, kind: str = TEXT) -> Note:
        note = Note(kind=kind)
        if kind == LIST:
            note.items = [Item()]
        self.notes.insert(0, note)
        return note

    def get(self, note_id: str) -> Note | None:
        return next((n for n in self.notes if n.id == note_id), None)

    def delete(self, note: Note) -> int:
        """Remove a note, returning where it was so undo can put it back."""
        try:
            index = self.notes.index(note)
        except ValueError:
            return -1
        self.notes.pop(index)
        return index

    def restore(self, note: Note, index: int) -> None:
        self.notes.insert(max(0, min(index, len(self.notes))), note)

    def drop_empty(self, note: Note) -> bool:
        """Discard a note nobody typed anything into. True if it went."""
        if note.is_empty:
            return self.delete(note) >= 0
        return False

    def sections(self, query: str = "") -> tuple[list[Note], list[Note]]:
        """(pinned, others), each newest-edited first -- Keep's two sections."""
        matching = [n for n in self.notes if n.matches(query)]
        matching.sort(key=lambda n: n.edited, reverse=True)
        return (
            [n for n in matching if n.pinned],
            [n for n in matching if not n.pinned],
        )
