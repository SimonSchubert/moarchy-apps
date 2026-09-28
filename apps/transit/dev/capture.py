#!/usr/bin/python3
"""Record what Transitous answers, under the URLs Transit asks with, for the shots.

A departure board photographs badly against the real thing: it is a different
board every minute, and at night it is empty. So this asks the questions
Transit asks once -- for Berlin, on an afternoon -- trims every answer to the
fields Api.mjs reads, and writes

  dev/fixture.json   NOW, the places the demo keeps, and the answers by URL

dev/demo.py puts it in front of each shot, where Motis.qml reads it when the
app runs with MOARCHY_TRANSIT_OFFLINE, and dev/shots pins the clock to NOW, so
"in 4 min" is four minutes every time. NOW is the start of the minute the
board was asked for: it waits for one to begin, so that the first departures
read "1 min", "2 min" and not a column of "now".

    python3 apps/transit/dev/capture.py

The URLs are built the way Api.mjs builds them, parameter for parameter: a
URL that differs by one character is a question the fixture cannot answer.
"""

from __future__ import annotations

import calendar
import json
import math
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASE = "https://api.transitous.org"
AGENT = "omarchy-transit/1.1.0 (+https://github.com/SimonSchubert/omarchy-transit)"
LANG = "en"
BERLIN = (52.52, 13.405)

# What the demo keeps, by the text typed into the picker. The first STOP (or
# PLACE) the geocoder offers is the one Transit would have stored.
PLACES = {
    "alex": ("Alexanderplatz", "STOP"),
    "hbf": ("Berlin Hauptbahnhof", "STOP"),
    "tor": ("Brandenburger Tor", "STOP"),
    "gallery": ("East Side Gallery", "PLACE"),
    "home": ("Görlitzer Bahnhof", "STOP"),
    "work": ("Friedrichstr", "STOP"),
    "airport": ("Flughafen BER", "STOP"),
    "warschauer": ("Warschauer", "STOP"),
}
# Saved trips, in order: the Journey tab looks up the first three.
TRIPS = [("home", "work"), ("work", "home"), ("hbf", "airport")]
# The search the results and the journey shots show.
SEARCH = ("tor", "gallery")
BOARD = "alex"


# ------------------------------------------------------------ Api.mjs, again

def enc(v: object) -> str:
    # encodeURIComponent's unreserved set.
    return urllib.parse.quote(str(v), safe="-_.!~*'()")


def qs(params: list[tuple[str, object]]) -> str:
    return "&".join(f"{k}={enc(v)}" for k, v in params if v not in (None, ""))


def round6(x: float) -> str:
    # Math.round(x * 1e6) / 1e6, printed the way JavaScript prints a number.
    r = math.floor(x * 1e6 + 0.5) / 1e6
    return str(int(r)) if r == int(r) else repr(r)


def place_param(p: dict) -> str:
    if p["type"] == "STOP" and p.get("id"):
        return p["id"]
    return f"{round6(p['lat'])},{round6(p['lon'])}"


def geocode_url(text: str, stops_only: bool) -> str:
    return BASE + "/api/v1/geocode?" + qs([
        ("text", text), ("type", "STOP" if stops_only else ""), ("language", LANG),
        ("place", f"{round6(BERLIN[0])},{round6(BERLIN[1])}"), ("placeBias", 2)])


def plan_url(a: dict, b: dict) -> str:
    return BASE + "/api/v6/plan?" + qs([
        ("fromPlace", place_param(a)), ("toPlace", place_param(b)), ("numItineraries", 6), ("language", LANG)])


def stoptimes_url(stop: dict) -> str:
    return BASE + "/api/v6/stoptimes?" + qs([("stopId", stop["id"]), ("n", 40), ("language", LANG)])


def trip_url(trip_id: str) -> str:
    return BASE + "/api/v6/trip?" + qs([("tripId", trip_id), ("language", LANG)])


def area_of(p: dict) -> str:
    town = region = ""
    for a in p.get("areas") or []:
        if not isinstance(a, dict) or not isinstance(a.get("name"), str):
            continue
        if a.get("default") and not town:
            town = a["name"]
        if a.get("adminLevel") == 4 and not region:
            region = a["name"]
    name = p.get("name", "")
    parts = []
    if town and town not in name:
        parts.append(town)
    if region and region != town and not parts and region not in name:
        parts.append(region)
    if p.get("country"):
        parts.append(p["country"][:3])
    return ", ".join(parts)


def keep_place(p: dict) -> dict:
    """A geocoder hit as Store.qml keeps it (Api.cleanPlace)."""
    return {"id": p["id"], "name": p["name"], "type": p["type"], "lat": p["lat"], "lon": p["lon"],
            "area": area_of(p), "modes": [m for m in p.get("modes") or [] if isinstance(m, str)][:12]}


# ------------------------------------------------------------ trimming

def pick(d: dict | None, keys: tuple[str, ...]) -> dict:
    return {k: d[k] for k in keys if isinstance(d, dict) and k in d}


def alerts(xs: object) -> list:
    return [pick(a, ("headerText", "descriptionText", "severityLevel", "effect")) for a in (xs or [])][:6]


PLACE_KEYS = ("name", "stopId", "lat", "lon", "arrival", "departure", "scheduledArrival",
              "scheduledDeparture", "track", "scheduledTrack", "cancelled")
LINE_KEYS = ("mode", "displayName", "routeShortName", "tripShortName", "routeColor", "routeTextColor",
             "headsign", "agencyName", "tripId", "realTime", "wheelchairAccessible", "bikesAllowed")


def place(p: dict | None) -> dict | None:
    if not p:
        return None
    out = pick(p, PLACE_KEYS)
    if p.get("alerts"):
        out["alerts"] = alerts(p["alerts"])
    return out


def leg(x: dict) -> dict:
    out = pick(x, LINE_KEYS + ("startTime", "endTime", "scheduledStartTime", "scheduledEndTime",
                               "duration", "distance", "cancelled"))
    out["from"] = place(x.get("from"))
    out["to"] = place(x.get("to"))
    if x.get("alerts"):
        out["alerts"] = alerts(x["alerts"])
    if x.get("intermediateStops"):
        out["intermediateStops"] = [place(s) for s in x["intermediateStops"]]
    return out


def itinerary(it: dict) -> dict:
    return pick(it, ("startTime", "endTime", "duration", "transfers")) | {"legs": [leg(x) for x in it.get("legs", [])]}


def plan(j: dict) -> dict:
    return {"itineraries": [itinerary(i) for i in j.get("itineraries", [])],
            "direct": [itinerary(i) for i in j.get("direct", [])][:2]} | pick(j, ("previousPageCursor", "nextPageCursor"))


def stoptimes(j: dict) -> dict:
    rows = []
    for s in j.get("stopTimes", [])[:120]:
        r = pick(s, LINE_KEYS + ("cancelled", "tripCancelled")) | {"place": place(s.get("place"))}
        for k in ("tripFrom", "tripTo"):
            if s.get(k):
                r[k] = pick(s[k], ("name",))
        rows.append(r)
    return {"stopTimes": rows, "place": place(j.get("place"))} | pick(j, ("previousPageCursor", "nextPageCursor"))


# ------------------------------------------------------------ asking

last = 0.0


def get(url: str) -> object:
    # Transitous is run by volunteers: one request at a time, a second apart.
    global last
    time.sleep(max(0.0, last + 1.0 - time.time()))
    last = time.time()
    out = subprocess.run(["curl", "-sS", "-f", "--compressed", "--max-time", "40",
                          "-H", "Accept: application/json", "-H", f"User-Agent: {AGENT}", url],
                         check=True, capture_output=True).stdout
    return json.loads(out)


def main() -> int:
    places: dict[str, dict] = {}
    for key, (text, kind) in PLACES.items():
        hits = get(geocode_url(text, kind == "STOP"))
        hit = next((h for h in hits if h.get("type") == kind), None)
        if not hit:
            print(f"no {kind} for {text!r}", file=sys.stderr)
            return 1
        places[key] = keep_place(hit)
        print(f"{key:10} {hit['name']}", file=sys.stderr)

    now = (int(time.time()) // 60 + 1) * 60
    time.sleep(max(0.0, now + 1 - time.time()))
    answers: dict[str, object] = {}
    board_url = stoptimes_url(places[BOARD])
    board = stoptimes(get(board_url))
    answers[board_url] = board

    for a, b in TRIPS[:3] + [SEARCH]:
        u = plan_url(places[a], places[b])
        answers[u] = plan(get(u))
        print(f"plan {a}->{b}: {len(answers[u]['itineraries'])}", file=sys.stderr)

    # The trip a board row opens: a live metro a few minutes out, whose
    # timeline has a coloured line and a platform on it.
    soon = [r for r in board["stopTimes"]
            if r.get("realTime") and not r.get("cancelled") and r.get("mode") == "SUBWAY"
            and r["place"].get("track")
            and calendar.timegm(time.strptime(r["place"]["departure"], "%Y-%m-%dT%H:%M:%SZ")) >= now + 180]
    row = soon[0] if soon else board["stopTimes"][0]
    answers[trip_url(row["tripId"])] = itinerary(get(trip_url(row["tripId"])))

    # The journey the detail shots open, by its place in the results list
    # (ResultsView sorts by planned start, then arrival): the first with a
    # change in it, which is the timeline worth showing.
    def ms(t: str | None) -> int:
        return calendar.timegm(time.strptime(t, "%Y-%m-%dT%H:%M:%SZ")) if t else 0

    its = answers[plan_url(places[SEARCH[0]], places[SEARCH[1]])]["itineraries"]
    order = sorted(its, key=lambda it: (ms(it["legs"][0].get("scheduledStartTime") or it["legs"][0].get("startTime")),
                                        ms(it["legs"][-1].get("endTime"))))
    journey = next((i for i, it in enumerate(order) if it.get("transfers", 0) >= 1), 0)

    fixture = {"NOW": now, "PLACES": places, "TRIPS": TRIPS, "SEARCH": SEARCH, "BOARD": BOARD,
               "JOURNEY": journey, "TRIP": row["tripId"], "answers": answers}
    (HERE / "fixture.json").write_text(json.dumps(fixture, ensure_ascii=False) + "\n")
    print(f"{len(answers)} answers, NOW {now}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
