#!/usr/bin/python3
"""Put the recorded answers in front of Transit, and a person's places beside them.

dev/capture.py wrote dev/fixture.json: what Transitous said, by the URL
Transit asks with. This copies it into MOARCHY_TRANSIT_DIR, where Motis.qml
reads it when the app runs with MOARCHY_TRANSIT_OFFLINE, and writes the
preferences Transit keeps in ~/.local/state/transit -- home and work, the
favourite stop, three saved trips and a few recent searches, all made of the
places capture.py looked up -- so every tab has something on it and no
request leaves the app.

    MOARCHY_TRANSIT_DIR=/tmp/transit python3 apps/transit/dev/demo.py

The snapshot in ~/.cache/transit is written empty: what is on screen comes
from the fixture, shaped by the app's own code, not from a copy of it.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main() -> int:
    src = HERE / "fixture.json"
    if not src.exists():
        print("no dev/fixture.json -- run dev/capture.py", file=sys.stderr)
        return 1
    home = Path.home()
    dest = Path(os.environ.get("MOARCHY_TRANSIT_DIR") or
                Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share") / "moarchy-transit")
    state = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state") / "transit"
    cache = Path(os.environ.get("XDG_CACHE_HOME") or home / ".cache") / "transit"
    for d in (dest, state, cache):
        d.mkdir(parents=True, exist_ok=True, mode=0o700)
    shutil.copy(src, dest / "fixture.json")

    fx = json.loads(src.read_text())
    p = fx["PLACES"]

    def trip(a: str, b: str) -> dict:
        return {"from": p[a], "to": p[b]}

    search = trip(*fx["SEARCH"])
    prefs = {
        "version": 1,
        "homePlace": p["home"],
        "workPlace": p["work"],
        # One: a second puts a row of stop chips over the board, and the
        # phone's board is about the departures.
        "stops": [p[fx["BOARD"]]],
        "trips": [trip(a, b) for a, b in fx["TRIPS"]],
        # Newest first: the search the results shots open, then two that are
        # not saved, for the Journey tab's Recent list.
        "recents": [search, trip("alex", "warschauer"), trip("home", "hbf")],
        "board": p[fx["BOARD"]],
        "clock24": True,
        "lastTab": "journey",
        "launcher": True,
        "launcherAdded": True,
    }
    for path, body in ((state / "prefs.json", json.dumps(prefs, ensure_ascii=False, indent=1)),
                       (cache / "snapshot.json", json.dumps({"version": 1, "entries": {}}))):
        path.write_text(body + "\n")
        path.chmod(0o600)
    return 0


if __name__ == "__main__":
    sys.exit(main())
