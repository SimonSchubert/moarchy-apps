#!/usr/bin/python3
"""Put the recorded answers in front of Couch, and somebody's lists beside them.

dev/capture.py wrote dev/fixture.json: what Trakt said to nobody in
particular, by the URL Couch asks with. This makes the rest -- the answers
only a signed-in person gets: Up next, the calendar of their shows and
movies, the watchlist, what they watched and rated -- out of those same
public titles, with progress made up here, and writes

  $MOARCHY_COUCH_FOR_TRAKT_DIR/fixture.json    every answer, by URL, which
                                               Couch reads when it runs with
                                               MOARCHY_COUCH_FOR_TRAKT_OFFLINE
  ~/.local/state/couch/prefs.json              signed in, as "jamie", with a
                                               token that is plainly not one

so every tab has something on it and no socket is opened.

    HOME=/tmp/couch MOARCHY_COUCH_FOR_TRAKT_DIR=/tmp/couch/fixture python3 apps/couch-for-trakt/dev/demo.py

MOARCHY_COUCH_FOR_TRAKT_TYPE=show opens Discover and the watchlist on shows.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASE = "https://api.trakt.tv"
TOKEN = "demo-token-not-a-real-one"
USER = {
    "username": "jamie",
    "slug": "jamie",
    "name": "Jamie",
    "avatar": "",
    "vip": False,
    "joined": "",
}

# How far behind "you" are in each show you watch, and how many hours ago
# you last watched it: made up, and fixed, so every run is the same.
BEHIND = [0, 2, 1, 0, 4, 1, 3, 0]
HOURS = [3, 20, 27, 49, 70, 96, 140, 190]


def iso(t: dt.datetime) -> str:
    return t.strftime("%Y-%m-%dT%H:%M:%S.000Z")


def when(s: str) -> dt.datetime:
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def main() -> int:
    src = HERE / "fixture.json"
    if not src.exists():
        print("no dev/fixture.json -- run dev/capture.py", file=sys.stderr)
        return 1
    fx = json.loads(src.read_text())
    ans: dict[str, object] = dict(fx["answers"])
    now = dt.datetime.fromtimestamp(fx["NOW"], dt.timezone.utc)
    start = dt.datetime.fromisoformat(fx["START"]).replace(tzinfo=dt.timezone.utc)

    def listed(kind: str, section: str) -> list[dict]:
        ext = (
            "boxoffice?extended=full,images,colors"
            if section == "boxoffice"
            else f"{section}?extended=full,images,colors&page=1&limit=36"
        )
        # Popular is a bare list of titles; the rest wrap each one.
        return [e.get(kind[:-1]) or e for e in ans.get(f"{BASE}/{kind}/{ext}") or []]

    shows: dict[int, dict] = {}
    for sec in ("trending", "popular", "anticipated"):
        for e in listed("shows", sec):
            shows.setdefault(e["ids"]["trakt"], e)

    # ---------------------------------------------------------- the shows you watch
    upnext, calendar, history = [], [], []
    hid = 900000
    for n, sid in enumerate(fx["WATCHING"]):
        show = shows[sid]
        seasons = ans[f"{BASE}/shows/{sid}/seasons?extended=full,images"]
        eps: list[dict] = []
        for s in seasons:
            eps += (
                ans.get(
                    f"{BASE}/shows/{sid}/seasons/{s['number']}?extended=full,images"
                )
                or []
            )
        aired = [
            e for e in eps if e.get("first_aired") and when(e["first_aired"]) <= now
        ]
        if not aired:
            continue
        behind = min(BEHIND[n % len(BEHIND)], len(aired) - 1)
        nxt = aired[-1 - behind]
        total = sum(s.get("aired_episodes", 0) for s in seasons if s["number"] > 0)
        last = now - dt.timedelta(hours=HOURS[n % len(HOURS)])
        progress = {
            "aired": total,
            "completed": max(0, total - behind - 1),
            "last_watched_at": iso(last),
            "next_episode": nxt,
        }
        upnext.append({"show": show, "progress": progress})

        # Watched: every season before the next episode's, and its season up to it.
        done = []
        for s in seasons:
            if s["number"] <= 0:
                continue
            upto = (
                s.get("aired_episodes", 0)
                if s["number"] < nxt["season"]
                else nxt["number"] - 1
                if s["number"] == nxt["season"]
                else 0
            )
            done.append(
                {
                    "number": s["number"],
                    "episodes": [
                        {"number": k, "completed": k <= upto}
                        for k in range(1, (s.get("aired_episodes") or 0) + 1)
                    ],
                }
            )
        ans[f"{BASE}/shows/{sid}/progress/watched?hidden=false&specials=false"] = (
            progress | {"seasons": done}
        )

        before = [
            e
            for e in aired
            if (e["season"], e["number"]) < (nxt["season"], nxt["number"])
        ][-2:]
        for k, e in enumerate(reversed(before)):
            hid += 1
            history.append(
                {
                    "id": hid,
                    "watched_at": iso(last - dt.timedelta(hours=k * 26)),
                    "action": "watch",
                    "type": "episode",
                    "episode": e,
                    "show": show,
                }
            )

        for e in eps:
            if e.get("first_aired") and start <= when(
                e["first_aired"]
            ) < start + dt.timedelta(days=15):
                calendar.append(
                    {"first_aired": e["first_aired"], "episode": e, "show": show}
                )
    upnext.sort(key=lambda r: r["progress"]["last_watched_at"], reverse=True)

    ans[f"{BASE}/sync/progress/up_next?extended=full,images&page=1&limit=40"] = upnext
    ans[f"{BASE}/calendars/my/shows/{fx['START']}/15?extended=full,images"] = calendar

    # ---------------------------------------------------------- movies
    movies: dict[int, dict] = {}
    for sec in ("trending", "popular", "anticipated", "boxoffice"):
        for e in listed("movies", sec):
            movies.setdefault(e["ids"]["trakt"], e)
    soon = [
        m
        for m in movies.values()
        if m.get("released")
        and start.date()
        <= dt.date.fromisoformat(m["released"])
        < start.date() + dt.timedelta(days=60)
    ]
    ans[f"{BASE}/calendars/my/movies/{fx['START']}/60?extended=full,images"] = [
        {"released": m["released"], "movie": m} for m in soon[:12]
    ]

    seen = listed("movies", "popular")[:10]
    for k, m in enumerate(seen[:5]):
        hid += 1
        history.append(
            {
                "id": hid,
                "watched_at": iso(now - dt.timedelta(hours=30 + k * 41)),
                "action": "watch",
                "type": "movie",
                "movie": m,
            }
        )
    history.sort(key=lambda r: r["watched_at"], reverse=True)
    ans[f"{BASE}/sync/history?extended=full,images&page=1&limit=40"] = history
    ans[f"{BASE}/sync/watched/movies?page=1&limit=250"] = [
        {"plays": 1 + k % 3, "movie": {"ids": m["ids"]}} for k, m in enumerate(seen)
    ]
    ans[f"{BASE}/sync/ratings?page=1&limit=250"] = [
        {"rating": r, "type": "movie", "movie": {"ids": m["ids"]}}
        for r, m in zip([9, 8, 10, 7, 8], seen)
    ] + [{"rating": 9, "type": "show", "show": {"ids": shows[fx["SHOW"]]["ids"]}}]

    # The watchlist: what is coming, and some of what everybody liked.
    def watchlist(kind: str, items: list[dict]) -> list[dict]:
        return [
            {
                "listed_at": iso(now - dt.timedelta(hours=9 + k * 31)),
                "type": kind,
                kind: m,
            }
            for k, m in enumerate(items)
        ]

    wl_movies = listed("movies", "anticipated")[:8] + listed("movies", "trending")[4:12]
    wl_shows = [
        m
        for m in listed("shows", "anticipated")[:6] + listed("shows", "popular")[:8]
        if m["ids"]["trakt"] not in fx["WATCHING"]
    ]
    for kind, items in (("movies", wl_movies), ("shows", wl_shows)):
        ans[
            f"{BASE}/sync/watchlist/{kind}/added/desc?extended=full,images,colors&page=1&limit=250"
        ] = watchlist(kind[:-1], items)

    ans[f"{BASE}/users/settings"] = {
        "user": {
            "username": USER["username"],
            "name": USER["name"],
            "vip": False,
            "ids": {"slug": USER["slug"]},
            "joined_at": "2019-04-02T18:00:00.000Z",
        }
    }
    ans[f"{BASE}/users/{USER['slug']}/stats"] = {
        "movies": {"watched": 412, "minutes": 49820},
        "shows": {"watched": 63},
        "episodes": {"watched": 2388, "minutes": 101640},
        "ratings": {"total": 297},
    }

    dest = Path(os.environ.get("MOARCHY_COUCH_FOR_TRAKT_DIR") or HERE / ".demo")
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "fixture.json").write_text(
        json.dumps(ans, ensure_ascii=False, separators=(",", ":")) + "\n"
    )

    # Signed in. Never over somebody's real sign-in: a prefs.json that holds
    # a token other than this one is left alone.
    home = Path.home()
    state = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state") / "couch"
    prefs = state / "prefs.json"
    if prefs.exists():
        try:
            old = (json.loads(prefs.read_text()).get("auth") or {}).get("access")
        except ValueError:
            old = None
        if old and old != TOKEN:
            print(f"{prefs} holds a real sign-in; not touching it", file=sys.stderr)
            return 1
    kind = (
        "show" if os.environ.get("MOARCHY_COUCH_FOR_TRAKT_TYPE") == "show" else "movie"
    )
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    prefs.write_text(
        json.dumps(
            {
                "version": 1,
                "lastTab": "discover",
                "mediaType": kind,
                "section": "trending",
                "watchlistType": kind,
                "calendar": "shows",
                "clientId": "",
                "clientSecret": "",
                "hideSpoilers": False,
                "launcher": True,
                "launcherAdded": True,
                "auth": {
                    "access": TOKEN,
                    "refresh": TOKEN,
                    "expires": 4102444800000,
                    "user": USER,
                },
            },
            indent=1,
        )
        + "\n"
    )
    prefs.chmod(0o600)
    return 0


if __name__ == "__main__":
    sys.exit(main())
