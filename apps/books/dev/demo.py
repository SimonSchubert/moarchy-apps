#!/usr/bin/python3
"""Put the recorded answers in front of Books, and a reading list beside them.

dev/capture.py wrote dev/fixture.json: what Open Library said, by the key
Books asks with, and the books it found for the reading list as "lib:<id>".
This copies the fixture into the data folder, where the app reads it when it
runs with MOARCHY_BOOKS_OFFLINE, and writes a library.json of those books --
two being read, part-way through, six wanted, nine read this year with stars
-- so every tab has something on it and no socket is opened.

    MOARCHY_BOOKS_DIR=/tmp/books python3 apps/books/dev/demo.py
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DAY = 86400


def book(doc: dict) -> dict:
    names = doc.get("author_name") or []
    keys = doc.get("author_key") or []
    return {
        "id": doc["key"].split("/")[-1], "title": doc.get("title", "Untitled"), "subtitle": doc.get("subtitle", ""),
        "authors": [{"id": keys[i] if i < len(keys) else "", "name": n} for i, n in enumerate(names[:4])],
        "cover": doc.get("cover_i") or 0, "year": doc.get("first_publish_year") or 0,
        "pages": doc.get("number_of_pages_median") or 0, "editions": doc.get("edition_count") or 0,
        "rating": doc.get("ratings_average") or 0, "ratings": doc.get("ratings_count") or 0,
    }


def main() -> int:
    dest = Path(os.environ.get("MOARCHY_BOOKS_DIR") or
                Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "moarchy-books")
    src = HERE / "fixture.json"
    if not src.exists():
        print("no dev/fixture.json -- run dev/capture.py", file=sys.stderr)
        return 1
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy(src, dest / "fixture.json")
    fx = json.loads(src.read_text())
    now = fx["NOW"]

    lib = [v for k, v in fx.items() if k.startswith("lib:")]
    books = []
    # Where each one is, so the pictures say something: a third of the way
    # through one, nearly done with the other.
    through = [0.35, 0.82]
    stars = [5, 4, 5, 3, 4, 5, 4, 3, 5]
    n = {"reading": 0, "want": 0, "read": 0}
    for entry in lib:
        shelf = entry["shelf"]
        i = n[shelf]
        n[shelf] += 1
        b = book(entry["doc"])
        b["shelf"] = shelf
        b["added"] = now - DAY * (40 + i * 9)
        b["page"] = 0
        b["stars"] = 0
        if shelf == "reading":
            b["started"] = now - DAY * (6 + i * 11)
            b["added"] = b["started"]
            b["page"] = round((b["pages"] or 300) * through[i % len(through)])
        if shelf == "read":
            b["finished"] = now - DAY * (4 + i * 23)
            b["page"] = b["pages"]
            b["stars"] = stars[i % len(stars)]
        books.append(b)

    (dest / "library.json").write_text(json.dumps({"version": 1, "books": books}, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
