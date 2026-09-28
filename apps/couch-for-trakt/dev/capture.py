#!/usr/bin/python3
"""Record what Trakt answers, under the URLs Couch asks with, for the shots.

A movie tracker photographs badly against the real thing: trending is
different every hour, and "your" lists would be somebody's own. So this asks
the public questions Couch asks once -- what is trending, popular, anticipated
and streaming, the premieres, a few shows' seasons and one show's and one
movie's page -- with Couch's own app key and no account, trims each answer to
the fields Api.mjs shape() reads, and writes

  dev/fixture.json   the answers, by URL (Trakt.qml offline)
  dev/.images/       the pictures, and an index.json of URL -> file
                     (MOARCHY_COUCH_FOR_TRAKT_IMAGES; not committed: they are
                     the studios' pictures, not ours)

Nothing here signs in or asks for anybody's lists. dev/demo.py makes the
signed-in views -- Up next, the calendar, the watchlist, history -- out of
these public titles, with made-up progress, in front of each shot, and
dev/shots pins the clock to NOW in the fixture, so "in 3 days" is three days
every time.

    python3 apps/couch-for-trakt/dev/capture.py
    python3 apps/couch-for-trakt/dev/capture.py --pictures   # the pictures again, same answers
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
APP = HERE.parent
BASE = "https://api.trakt.tv"
AGENT = "couch-for-trakt-capture (+https://github.com/SimonSchubert/moarchy-apps)"
PER_PAGE = 36  # DiscoverView.perPage
WATCHING = 8  # shows "you" are watching, for Up next and the calendar
LIST_EXT = "full,images,colors"


def key() -> str:
    m = re.search(r'CLIENT_ID\s*=\s*"([^"]+)"', (APP / "Keys.mjs").read_text())
    if not m:
        sys.exit("no CLIENT_ID in Keys.mjs")
    return m.group(1)


CLIENT_ID = key()


# ------------------------------------------------------------ URLs, as Api.mjs builds them


def plural(t: str) -> str:
    return "shows" if t == "show" else "movies"


def discover_url(t: str, section: str, page: int = 1) -> str:
    p = f"{BASE}/{plural(t)}/"
    if section == "boxoffice":
        return p + "boxoffice?extended=" + LIST_EXT
    p += "streaming/weekly" if section == "streaming" else section
    return f"{p}?extended={LIST_EXT}&page={page}&limit={PER_PAGE}"


def summary_url(t: str, i: int) -> str:
    return f"{BASE}/{plural(t)}/{i}?extended=full,images,colors"


def people_url(t: str, i: int) -> str:
    return f"{BASE}/{plural(t)}/{i}/people?extended=images"


def related_url(t: str, i: int) -> str:
    return f"{BASE}/{plural(t)}/{i}/related?extended=full,images&limit=18"


def seasons_url(i: int) -> str:
    return f"{BASE}/shows/{i}/seasons?extended=full,images"


def season_url(i: int, n: int) -> str:
    return f"{BASE}/shows/{i}/seasons/{n}?extended=full,images"


def calendar_url(target: str, what: str, start: str, days: int) -> str:
    return f"{BASE}/calendars/{target}/{what}/{start}/{days}?extended=full,images"


# Api.image(): Trakt's bare "host/path", at the rendition the app asks for.
def image(lst: object, size: str) -> str:
    v = str(lst[0] or "") if isinstance(lst, list) and lst else ""
    v = re.sub(r"^https?://", "", v, flags=re.I)
    if not re.fullmatch(r"[a-z0-9.-]+\.trakt\.tv/[A-Za-z0-9._/-]+", v):
        return ""
    v = re.sub(r"/(thumb|medium|full)/", f"/{size}/", v, count=1)
    v = re.sub(r"\.(jpe?g|png)\.webp$", r".\1", v, flags=re.I)
    return "https://" + v


# ------------------------------------------------------------ asking


def get(url: str) -> object:
    req = urllib.request.Request(
        url,
        headers={
            "Content-Type": "application/json",
            "trakt-api-version": "2",
            "trakt-api-key": CLIENT_ID,
            "User-Agent": AGENT,
        },
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                body = r.read()
            time.sleep(0.25)
            return json.loads(body) if body else []
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 3:
                time.sleep(int(e.headers.get("retry-after") or 10))
                continue
            raise
    raise RuntimeError(url)


# ------------------------------------------------------------ trimming, to what shape() reads

MEDIA = (
    "title",
    "year",
    "rating",
    "votes",
    "runtime",
    "genres",
    "certification",
    "first_aired",
    "released",
    "status",
    "network",
    "overview",
    "tagline",
    "trailer",
    "homepage",
    "country",
    "language",
    "aired_episodes",
    "airs",
    "comment_count",
)
EPISODE = (
    "season",
    "number",
    "title",
    "first_aired",
    "runtime",
    "rating",
    "episode_type",
    "overview",
)
SEASON = ("number", "title", "episode_count", "aired_episodes", "rating", "first_aired")


def pick(o: dict, keys: tuple) -> dict:
    return {k: o[k] for k in keys if k in o and o[k] is not None}


def ids(o: dict, *keys: str) -> dict:
    return {
        k: v for k, v in (o.get("ids") or {}).items() if k in keys and v is not None
    }


def pics(o: dict, *keys: str) -> dict:
    im = o.get("images") or {}
    return {k: im[k][:1] for k in keys if im.get(k)}


def media(o: dict) -> dict:
    m = pick(o, MEDIA) | {"ids": ids(o, "trakt", "slug", "imdb")}
    if o.get("overview"):
        m["overview"] = o["overview"][:1200]
    p = pics(o, "poster", "fanart", "logo")
    if p:
        m["images"] = p
    if (o.get("colors") or {}).get("poster"):
        m["colors"] = {"poster": o["colors"]["poster"][:1]}
    return m


def episode(e: dict) -> dict:
    out = pick(e, EPISODE) | {"ids": ids(e, "trakt")}
    p = pics(e, "screenshot")
    if p:
        out["images"] = p
    return out


def entry(e: dict) -> dict:
    out = pick(
        e, ("watchers", "list_count", "revenue", "listed_at", "first_aired", "released")
    )
    for k in ("movie", "show"):
        if isinstance(e.get(k), dict):
            out[k] = media(e[k])
    if isinstance(e.get("episode"), dict):
        out["episode"] = episode(e["episode"])
    if "ids" in e:
        out |= media(e)
    return out


def people(p: dict) -> dict:
    cast = []
    for c in (p.get("cast") or [])[:30]:
        person = c.get("person") or {}
        one = {
            "characters": c.get("characters")
            or ([c["character"]] if c.get("character") else []),
            "person": {"name": person.get("name"), "ids": ids(person, "slug")},
        }
        im = c.get("images") or person.get("images") or {}
        if im.get("headshot"):
            one["images"] = {"headshot": im["headshot"][:1]}
        cast.append(one)
    crew = {}
    for job in ("created by", "directing", "writing"):
        crew[job] = [
            {
                "jobs": c.get("jobs") or [c.get("job")],
                "person": {"name": (c.get("person") or {}).get("name")},
            }
            for c in ((p.get("crew") or {}).get(job) or [])[:8]
        ]
    return {"cast": cast, "crew": crew}


def season(s: dict) -> dict:
    out = pick(s, SEASON)
    p = pics(s, "poster")
    if p:
        out["images"] = p
    return out


# ------------------------------------------------------------ the pictures


def download(want: dict[str, None], out: Path) -> dict[str, str]:
    out.mkdir(exist_ok=True)
    index: dict[str, str] = {}
    for url in sorted(want):
        ext = ".png" if url.lower().endswith(".png") else ".jpg"
        name = hashlib.md5(url.encode()).hexdigest()[:20] + ext
        path = out / name
        if not path.exists():
            try:
                req = urllib.request.Request(url, headers={"User-Agent": AGENT})
                with urllib.request.urlopen(req, timeout=30) as r:
                    data = r.read()
                    kind = r.headers.get("content-type", "")
                if kind.startswith("image/") and data:
                    path.write_bytes(data)
            except urllib.error.URLError:
                pass
        if path.exists():
            index[url] = name
    (out / "index.json").write_text(json.dumps(index, indent=0, sort_keys=True) + "\n")
    return index


def main() -> int:
    # Noon UTC today: the same calendar day in every time zone the shots
    # might be run in, and nothing is "aired" that had not aired by then.
    today = dt.datetime.now(dt.timezone.utc).replace(
        hour=12, minute=0, second=0, microsecond=0
    )
    now = int(today.timestamp())
    start = (today - dt.timedelta(days=1)).strftime("%Y-%m-%d")
    answers: dict[str, object] = {}

    lists: dict[str, list] = {}
    for t, sections in (
        ("movie", ("trending", "popular", "anticipated", "streaming", "boxoffice")),
        ("show", ("trending", "popular", "anticipated", "streaming")),
    ):
        for s in sections:
            url = discover_url(t, s)
            try:
                answers[url] = lists[f"{t}:{s}"] = [entry(e) for e in get(url)]
            except urllib.error.HTTPError as e:
                # Streaming answers 404 at the moment; the app says so too.
                print(f"{t}:{s}", e, file=sys.stderr)
                lists[f"{t}:{s}"] = []
                continue
            print(f"{t}:{s}", len(lists[f"{t}:{s}"]), file=sys.stderr)

    for what in ("shows/premieres", "shows/new"):
        url = calendar_url("all", what, start, 21)
        answers[url] = [entry(e) for e in get(url)][:120]

    # The shows "you" are watching: on the air now, with pictures, as many
    # as can be with an episode in the calendar's two weeks.
    window = (
        (today - dt.timedelta(days=1)).replace(hour=0),
        today + dt.timedelta(days=14),
    )
    seen: set[int] = set()
    airing: list[int] = []
    resting: list[int] = []
    for e in lists["show:trending"] + lists["show:streaming"] + lists["show:popular"]:
        s = e.get("show") or e
        sid = s["ids"]["trakt"]
        if (
            sid in seen
            or s.get("status") != "returning series"
            or not (s.get("images") or {}).get("fanart")
        ):
            continue
        seen.add(sid)
        if (
            len(seen) > 30
            or len(airing) >= WATCHING - 2
            and len(airing) + len(resting) >= WATCHING
        ):
            break
        ss = [season(x) for x in get(seasons_url(sid))]
        numbered = [x for x in ss if x.get("number", 0) > 0]
        aired = [x for x in numbered if x.get("aired_episodes")]
        if not aired:
            continue
        answers[seasons_url(sid)] = ss
        on = aired[-1]["number"]
        for n in sorted({on, numbered[-1]["number"]}):
            answers[season_url(sid, n)] = [episode(x) for x in get(season_url(sid, n))]
        soon = any(
            window[0].isoformat()
            <= (x.get("first_aired") or "")[:19]
            < window[1].isoformat()
            for n in {on, numbered[-1]["number"]}
            for x in answers[season_url(sid, n)]
        )
        if soon and len(airing) < WATCHING - 2:
            airing.append(sid)
        elif len(resting) < WATCHING - len(airing):
            resting.append(sid)
    watching = (airing + resting)[:WATCHING]

    # One show's page and one movie's, whole.
    show, movie = watching[0], lists["movie:trending"][0]["movie"]["ids"]["trakt"]
    for t, i in (("show", show), ("movie", movie)):
        answers[summary_url(t, i)] = media(get(summary_url(t, i)))
        answers[people_url(t, i)] = people(get(people_url(t, i)))
        answers[related_url(t, i)] = [entry(e) for e in get(related_url(t, i))]

    fixture = {
        "NOW": now,
        "START": start,
        "WATCHING": watching,
        "SHOW": show,
        "MOVIE": movie,
        "answers": answers,
    }
    pictures(fixture)
    return 0


# The renditions each picture is asked for at: Api.mjs's thumb for a card,
# medium for a backdrop and a title's own page.
SIZES = {"poster": "thumb", "screenshot": "thumb", "headshot": "thumb"}


def pictures(fixture: dict) -> None:
    """Download what the shots draw, and take what is gone out of the answers."""
    answers = fixture["answers"]
    want: dict[str, None] = {}

    def add(u: str) -> None:
        if u:
            want[u] = None

    def walk(o: object, hero: bool) -> None:
        if isinstance(o, list):
            for x in o:
                walk(x, hero)
        elif isinstance(o, dict):
            im = o.get("images") or {}
            for k, size in SIZES.items():
                add(image(im.get(k), size))
            if hero:
                add(image(im.get("fanart"), "medium"))
            for k in ("movie", "show", "episode", "cast"):
                walk(o.get(k), hero)

    for url, v in answers.items():
        if "/calendars/" in url:
            walk(v[:40], False)
        elif isinstance(v, list) and ("&limit=36" in url or "/boxoffice?" in url):
            walk(v, False)
            walk(
                v[:8], True
            )  # the Hero's backdrops; Up next's, where an episode has no still
        elif "/seasons" in url or "/people?" in url or "/related?" in url:
            walk(v, False)
    for t, i in (("show", fixture["SHOW"]), ("movie", fixture["MOVIE"])):
        im = answers[summary_url(t, i)].get("images") or {}
        for k in ("poster", "fanart", "logo"):
            add(image(im.get(k), "medium"))
    for sid in fixture["WATCHING"]:
        for v in answers.values():
            if isinstance(v, list):
                for e in v:
                    s = e.get("show") if isinstance(e, dict) else None
                    s = s or (
                        e if isinstance(e, dict) and "aired_episodes" in e else None
                    )
                    if s and s.get("ids", {}).get("trakt") == sid:
                        add(image((s.get("images") or {}).get("fanart"), "medium"))

    index = download(want, HERE / ".images")

    # A picture the host no longer has is a title with no picture, which is
    # what the app would show for it anyway -- without a hole in the shot
    # where a still would be (Up next falls back to the show's backdrop).
    gone = {u for u in want if u not in index}

    def blank(o: object) -> None:
        if isinstance(o, list):
            for x in o:
                blank(x)
        elif isinstance(o, dict):
            im = o.get("images")
            if isinstance(im, dict):
                for k in list(im):
                    if image(im[k], SIZES.get(k, "medium")) in gone:
                        del im[k]
            for v in o.values():
                if isinstance(v, (dict, list)):
                    blank(v)

    blank(answers)
    (HERE / "fixture.json").write_text(
        json.dumps(fixture, ensure_ascii=False, separators=(",", ":")) + "\n"
    )
    print(
        f"{len(answers)} answers, {len(index)} pictures, {len(gone)} gone; watching {fixture['WATCHING']}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    # --pictures: only the pictures again, for the fixture there is.
    if sys.argv[1:] == ["--pictures"]:
        pictures(json.loads((HERE / "fixture.json").read_text()))
        sys.exit(0)
    sys.exit(main())
