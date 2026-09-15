"""Upcoming launches: what Launch Library says, and what a phone can do with it.

Nothing here imports GTK, which is what makes the half of this app that can be
wrong -- parsing somebody else's JSON, and turning a NET into the string a
person reads -- testable on any machine with a Python. The same split Coins
has between `market.py` and its window, and for the same reason.

**The endpoint is `/launch/upcoming/`, once, for the whole list.** One request
returns twenty launches with their NET, status, pad, vehicle and description,
which is every fact this app draws. The alternative -- a request per launch,
or `mode=detailed` for webcasts this app does not open -- is a second call
against a keyless limit of fifteen an hour.

**No API key is required and one is used if offered.** The keyless tier is
fifteen calls per hour per address, shared with everybody else behind the
same carrier NAT, so a 429 is an ordinary answer rather than an error --
`LaunchError.retry_after` carries what to do about it and the window backs
off. `MOARCHY_LAUNCHES_KEY` is sent as `Authorization: Token …`.

**Every field is optional except an id and a NET.** A TBC launch has no
probability, a list-mode row has no description, and a hold has no weather.
Each is dropped rather than being allowed to raise: a list of twenty that
refuses to draw because the eighth has a null in it is the failure mode to
design against.
"""

from __future__ import annotations

import http.client
import json
import math
import os
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone

API = "https://ll.thespacedevs.com/2.2.0/launch/upcoming/"

# Who is asking. Launch Library asks for a UA that identifies the client, and
# an app that names itself is one whose traffic can be recognised and blocked
# on its own rather than with every other keyless caller.
AGENT = "moarchy-launches/0.1.0 (+https://github.com/SimonSchubert/moarchy-apps)"

# Twelve seconds. A phone on a cell connection is slow rather than absent, and
# the fetch is on a thread either way, so nothing is waiting on this but the
# word "Updating" in the header.
TIMEOUT = 12.0

# How many launches the list holds. Twenty is a couple of days of the world's
# pads, is about 100 kB of JSON, and is as far down the NET as a person
# scrolls before they search instead. The endpoint's own ceiling is 100; we
# never paginate, because each page would be another of the fifteen.
LIMIT = 20
LIMIT_MAX = 100

# The most a response may be before it is refused unread. Twenty launches is
# a hundred kilobytes; four megabytes is a body that has gone wrong, and on a
# metered connection an unbounded read is the expensive kind of wrong.
MAX_BYTES = 4 * 1024 * 1024

# What a 429 costs when the answer did not say how long to wait. Fifteen an
# hour is a slot every four minutes.
RATE_LIMIT_S = 240.0

# How old the cache may get before the window asks again, and how that shortens
# when something is about to fly. Launch Library's own advice: fewer calls
# overall, more around T-0. A mapped window at rest is four an hour; one with
# a Go in the next ten minutes is still under the anonymous ceiling.
REFRESH_S = 15 * 60
NEAR_S = 60 * 60
IMMINENT_S = 10 * 60
NEAR_REFRESH_S = 5 * 60
IMMINENT_REFRESH_S = 2 * 60

# Launch Library status ids. Unknown ids still draw whatever abbrev arrived.
STATUS_GO = 1
STATUS_TBD = 2
STATUS_SUCCESS = 3
STATUS_FAILURE = 4
STATUS_HOLD = 5
STATUS_IN_FLIGHT = 6
STATUS_PARTIAL = 7
STATUS_TBC = 8

TERMINAL = frozenset({STATUS_SUCCESS, STATUS_FAILURE, STATUS_PARTIAL})
UNCERTAIN = frozenset({STATUS_TBD, STATUS_TBC})
LIVE = frozenset({STATUS_GO, STATUS_HOLD, STATUS_IN_FLIGHT})

# The disc is 36px. The API's "In Flight" / "Partial Failure" do not fit, so
# the badge carries a short mark and the detail page carries the real words.
# Colour is never the only signal: roughly one man in twelve cannot tell this
# app's green from its red.
DISC = {
    STATUS_GO: "GO",
    STATUS_TBD: "TBD",
    STATUS_SUCCESS: "OK",
    STATUS_FAILURE: "NO",
    STATUS_HOLD: "HLD",
    STATUS_IN_FLIGHT: "FLY",
    STATUS_PARTIAL: "PRT",
    STATUS_TBC: "TBC",
}

STATUS_HUE = {
    STATUS_GO: "green",
    STATUS_TBD: "yellow",
    STATUS_SUCCESS: "green",
    STATUS_FAILURE: "red",
    STATUS_HOLD: "yellow",
    STATUS_IN_FLIGHT: "cyan",
    STATUS_PARTIAL: "orange",
    STATUS_TBC: "yellow",
}

FINE = frozenset({"SEC", "MIN"})
HOUR = frozenset({"HR"})
MONTH = frozenset({"M", "MONTH"})
QUARTER = frozenset({"Q1", "Q2", "Q3", "Q4"})
YEAR = frozenset({"Y", "YEAR"})

DASH = "—"


class LaunchError(Exception):
    """Something a person can be told, and a hint about when to try again.

    Every failure in this module arrives as one of these carrying a sentence in
    plain words, because all of them end up in the same place: one line under a
    list of launches that are now older than they were. `retry_after` is
    seconds, and is 0 when the answer carried no such advice.
    """

    def __init__(self, message: str, *, retry_after: float = 0.0) -> None:
        super().__init__(message)
        self.retry_after = retry_after


@dataclass(frozen=True)
class Launch:
    """One row: everything drawn about a launch, and nothing else.

    Deliberately not the whole record. The endpoint returns nested agencies,
    maps, image URLs and attempt counts, and this app draws a name, a clock
    and a pad. Keeping the rest would make the cache five times the size for
    a screen that never shows them, and would invite a livestream page to be
    built out of whatever happened to be lying around rather than out of a
    request made for it.
    """

    id: str
    name: str
    vehicle: str
    agency: str
    status_id: int
    status: str
    net: datetime
    precision: str
    window_start: datetime | None
    window_end: datetime | None
    pad: str
    location: str
    orbit: str
    mission_type: str
    probability: int | None
    weather: str
    hold: str
    description: str

    def matches(self, query: str) -> bool:
        """Is this the launch somebody is typing the name of?

        The front of any word in the mission, the vehicle, the agency, the pad
        or the location. Not a substring anywhere: "ace" matching SpaceX means
        a search box that fills with coincidences, and the launch somebody
        means is almost always one whose name starts that way. Any *word*
        rather than the first one, because "canaveral" has to find the pad --
        which is the same rule a launcher uses on app names.
        """
        text = query.strip().lower()
        if not text:
            return True
        haystack = (
            f"{self.name} {self.vehicle} {self.agency} {self.pad} {self.location}"
        )
        return any(word.startswith(text) for word in _words(haystack))

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "vehicle": self.vehicle,
            "agency": self.agency,
            "status_id": self.status_id,
            "status": self.status,
            "net": _iso(self.net),
            "precision": self.precision,
            "window_start": _iso(self.window_start),
            "window_end": _iso(self.window_end),
            "pad": self.pad,
            "location": self.location,
            "orbit": self.orbit,
            "mission_type": self.mission_type,
            "probability": self.probability,
            "weather": self.weather,
            "hold": self.hold,
            "description": self.description,
        }

    @classmethod
    def from_dict(cls, data: dict) -> Launch:
        """One launch back out of our own cache file.

        Separate from `parse` below on purpose: that reads Launch Library's
        shape and this reads ours. Folding them together would mean a change
        to the API's field names quietly rewriting what a cache written last
        week means.
        """
        if not isinstance(data, dict):
            raise TypeError("launch is not a table")
        identifier = data.get("id")
        net = _datetime(data.get("net"))
        if not isinstance(identifier, str) or not identifier or net is None:
            raise ValueError("launch has no id or no NET")
        status_id = int(_number(data.get("status_id")) or 0)
        probability = _probability(data.get("probability"))
        return cls(
            id=identifier,
            name=str(data.get("name") or identifier),
            vehicle=str(data.get("vehicle") or ""),
            agency=str(data.get("agency") or ""),
            status_id=status_id,
            status=str(data.get("status") or DISC.get(status_id, DASH)),
            net=net,
            precision=str(data.get("precision") or ""),
            window_start=_datetime(data.get("window_start")),
            window_end=_datetime(data.get("window_end")),
            pad=str(data.get("pad") or ""),
            location=str(data.get("location") or ""),
            orbit=str(data.get("orbit") or ""),
            mission_type=str(data.get("mission_type") or ""),
            probability=probability,
            weather=str(data.get("weather") or ""),
            hold=str(data.get("hold") or ""),
            description=str(data.get("description") or ""),
        )


def _words(text: str) -> list[str]:
    words = []
    for raw in text.lower().split():
        word = raw.strip(".,;:()[]{}/|-")
        if word:
            words.append(word)
    return words


def _text(value: object) -> str:
    return value.strip() if isinstance(value, str) else ""


def _number(value: object) -> float | None:
    """A JSON number, or None for anything that is not one.

    `isinstance(True, int)` is True in Python, and a bool where a probability
    should be would otherwise become 1 and be drawn as 1%.
    """
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return None if math.isnan(number) or math.isinf(number) else number


def _probability(value: object) -> int | None:
    number = _number(value)
    if number is None or number < 0:
        # Launch Library uses -1 for "we have not been told".
        return None
    return int(number)


def _datetime(value: object) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def clock(now: datetime | None = None) -> datetime:
    """When 'now' is, for a countdown.

    `MOARCHY_LAUNCHES_NOW` freezes it so screenshots of T-12:00 agree with
    each other, and so the tests do not depend on the wall clock. A naive
    datetime is treated as UTC rather than as local, because every NET this
    app has ever seen is UTC.
    """
    if now is not None:
        if now.tzinfo is None:
            now = now.replace(tzinfo=timezone.utc)
        return now.astimezone(timezone.utc)
    frozen = os.environ.get("MOARCHY_LAUNCHES_NOW")
    if frozen:
        parsed = _datetime(frozen)
        if parsed is not None:
            return parsed
    return datetime.now(timezone.utc)


def parse(record: object) -> Launch | None:
    """One launch out of Launch Library's shape, or None if it is not usable.

    Accepts both the nested 'normal' payload this app asks for and the flatter
    `mode=list` shape, so a cache written against either still draws.
    """
    if not isinstance(record, dict):
        return None
    identifier = record.get("id")
    if not isinstance(identifier, str) or not identifier:
        return None
    net = _datetime(record.get("net"))
    if net is None:
        return None

    status_obj = record.get("status") if isinstance(record.get("status"), dict) else {}
    status_id = int(_number(status_obj.get("id")) or 0)
    status = _text(status_obj.get("abbrev")) or DISC.get(status_id, DASH)

    precision_obj = record.get("net_precision")
    if isinstance(precision_obj, dict):
        precision = _text(precision_obj.get("abbrev"))
    else:
        precision = _text(precision_obj)

    name, vehicle = _names(record)
    agency = _agency(record)
    pad_name, location = _pad(record)
    orbit, mission_type, description = _mission(record)

    return Launch(
        id=identifier,
        name=name or identifier,
        vehicle=vehicle,
        agency=agency,
        status_id=status_id,
        status=status,
        net=net,
        precision=precision,
        window_start=_datetime(record.get("window_start")),
        window_end=_datetime(record.get("window_end")),
        pad=pad_name,
        location=location,
        orbit=orbit,
        mission_type=mission_type,
        probability=_probability(record.get("probability")),
        weather=_text(record.get("weather_concerns")),
        hold=_text(record.get("holdreason")),
        description=description,
    )


def _names(record: dict) -> tuple[str, str]:
    mission = record.get("mission")
    if isinstance(mission, dict):
        name = _text(mission.get("name"))
    else:
        name = _text(mission)

    rocket = record.get("rocket")
    vehicle = ""
    if isinstance(rocket, dict):
        config = rocket.get("configuration")
        if isinstance(config, dict):
            vehicle = _text(config.get("full_name")) or _text(config.get("name"))

    raw = _text(record.get("name"))
    if " | " in raw:
        left, right = raw.split(" | ", 1)
        vehicle = vehicle or left.strip()
        name = name or right.strip()
    elif not name:
        name = raw
    return name, vehicle


def _agency(record: dict) -> str:
    lsp = record.get("launch_service_provider")
    if isinstance(lsp, dict):
        return _text(lsp.get("name"))
    return _text(record.get("lsp_name"))


def _pad(record: dict) -> tuple[str, str]:
    pad = record.get("pad")
    if isinstance(pad, dict):
        name = _text(pad.get("name"))
        location = pad.get("location")
        where = _text(location.get("name")) if isinstance(location, dict) else ""
        return name, where
    return _text(pad), _text(record.get("location"))


def _mission(record: dict) -> tuple[str, str, str]:
    mission = record.get("mission")
    if isinstance(mission, dict):
        orbit_obj = mission.get("orbit")
        if isinstance(orbit_obj, dict):
            orbit = _text(orbit_obj.get("abbrev")) or _text(orbit_obj.get("name"))
        else:
            orbit = _text(orbit_obj)
        return orbit, _text(mission.get("type")), _text(mission.get("description"))
    return _text(record.get("orbit")), _text(record.get("mission_type")), ""


def parse_upcoming(payload: object) -> list[Launch]:
    """The whole answer, with the unusable rows left out rather than fatal."""
    if not isinstance(payload, dict):
        raise LaunchError(
            "Launch Library sent something that is not a list of launches."
        )
    results = payload.get("results")
    if not isinstance(results, list):
        raise LaunchError(
            "Launch Library sent something that is not a list of launches."
        )
    launches = []
    for record in results:
        launch = parse(record)
        if launch is not None:
            launches.append(launch)
    if not launches and results:
        raise LaunchError(
            "Launch Library sent launches in a shape this app cannot read."
        )
    return launches


# --- the wire ------------------------------------------------------------


def _retry_after(error: urllib.error.HTTPError) -> float:
    header = error.headers.get("Retry-After") if error.headers else None
    if isinstance(header, str) and header.strip().isdigit():
        return float(header.strip())
    return 0.0


def _get(url: str, *, key: str = "", timeout: float = TIMEOUT) -> object:
    """One GET, and a sentence for every way it can fail."""
    request = urllib.request.Request(
        url, headers={"User-Agent": AGENT, "Accept": "application/json"}
    )
    if key:
        request.add_header("Authorization", f"Token {key}")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as exc:
        if exc.code == 429:
            raise LaunchError(
                "Launch Library is rate-limiting this connection.",
                retry_after=_retry_after(exc) or RATE_LIMIT_S,
            ) from exc
        if 500 <= exc.code < 600:
            raise LaunchError("Launch Library is having trouble.") from exc
        raise LaunchError(f"Launch Library refused the request ({exc.code}).") from exc
    except (OSError, http.client.HTTPException) as exc:
        raise LaunchError("No answer from Launch Library.") from exc
    if len(raw) > MAX_BYTES:
        raise LaunchError("Launch Library sent more than this app will read.")
    try:
        return json.loads(raw)
    except ValueError as exc:
        raise LaunchError("Launch Library sent something that is not JSON.") from exc


class Live:
    """Launch Library over HTTPS, which is the only thing in this app that is.

    An object rather than a function so that the window can be handed something
    else entirely: the tests pass a stand-in with this one method, and
    `MOARCHY_LAUNCHES_OFFLINE` passes nothing at all.
    """

    def __init__(
        self, *, key: str = "", timeout: float = TIMEOUT, count: int = LIMIT
    ) -> None:
        self.key = key
        self.timeout = timeout
        self.count = max(1, min(count, LIMIT_MAX))

    def _url(self) -> str:
        query = urllib.parse.urlencode({"limit": str(self.count)})
        return f"{API}?{query}"

    def upcoming(self) -> list[Launch]:
        """The next `count` launches, NET ascending, including the 24-hour tail."""
        return parse_upcoming(_get(self._url(), key=self.key, timeout=self.timeout))


# --- numbers as somebody reads them --------------------------------------


def disc(launch: Launch) -> str:
    """The three-or-four letters in the badge."""
    return DISC.get(launch.status_id) or (
        launch.status[:4].upper() if launch.status else DASH
    )


def hue(launch: Launch) -> str:
    """Which of the theme hues the badge wears."""
    return STATUS_HUE.get(launch.status_id, "blue")


def headline(launch: Launch, *, now: datetime | None = None) -> str:
    """The right-hand column: a countdown, an age, or a date."""
    moment = clock(now)
    if launch.status_id in TERMINAL:
        return freshness(max(0.0, (moment - launch.net).total_seconds()))
    if launch.status_id in UNCERTAIN or launch.precision not in FINE:
        precision = launch.precision if launch.precision not in FINE else "HR"
        return wall(launch.net, precision)
    return countdown(launch.net, moment)


def countdown(net: datetime, now: datetime) -> str:
    """T-04:21:07, or T-2d 04h once a day away."""
    seconds = int((net - now).total_seconds())
    sign = "-" if seconds >= 0 else "+"
    remaining = abs(seconds)
    days, rem = divmod(remaining, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, secs = divmod(rem, 60)
    if days:
        return f"T{sign}{days}d {hours:02d}h"
    return f"T{sign}{hours:02d}:{minutes:02d}:{secs:02d}"


def wall(net: datetime, precision: str) -> str:
    """A date a person can read, no ticking clock."""
    local = net.astimezone()
    mark = (precision or "").upper()
    if mark in YEAR:
        return local.strftime("%Y")
    if mark in QUARTER:
        quarter = (local.month - 1) // 3 + 1
        return f"Q{quarter} {local.year}"
    if mark in MONTH:
        return local.strftime("%b %Y")
    if mark in HOUR:
        return local.strftime("%d %b %H:%M")
    return local.strftime("%d %b")


def window(launch: Launch) -> str:
    """The open window, or empty when Launch Library did not send one."""
    if launch.window_start is None and launch.window_end is None:
        return ""
    start = launch.window_start or launch.net
    end = launch.window_end or start
    left = start.astimezone().strftime("%d %b %H:%M")
    if end <= start:
        return left
    if start.astimezone().date() == end.astimezone().date():
        return f"{left} – {end.astimezone().strftime('%H:%M')}"
    return f"{left} – {end.astimezone().strftime('%d %b %H:%M')}"


def tone(launch: Launch, *, now: datetime | None = None) -> str:
    """soon, late, wait or dim -- the class the countdown is drawn in."""
    if launch.status_id in UNCERTAIN:
        return "wait"
    if launch.status_id in TERMINAL:
        return "dim"
    remaining = (launch.net - clock(now)).total_seconds()
    if remaining < 0 and launch.status_id == STATUS_GO:
        return "late"
    if 0 <= remaining < 3600 and launch.status_id == STATUS_GO:
        return "soon"
    return "dim"


def freshness(seconds: float) -> str:
    """How old something is, in the words somebody would use."""
    if seconds < 60:
        return "just now"
    if seconds < 3600:
        return f"{int(seconds // 60)} min ago"
    if seconds < 86400:
        hours = int(seconds // 3600)
        return "1 hour ago" if hours == 1 else f"{hours} hours ago"
    days = int(seconds // 86400)
    return "yesterday" if days == 1 else f"{days} days ago"


def refresh_after(launches: list[Launch], *, now: datetime | None = None) -> float:
    """How old the cache may be before the next fetch, in seconds."""
    moment = clock(now)
    wait = float(REFRESH_S)
    for launch in launches:
        if launch.status_id not in LIVE:
            continue
        remaining = (launch.net - moment).total_seconds()
        if 0 <= remaining <= IMMINENT_S:
            wait = min(wait, IMMINENT_REFRESH_S)
        elif 0 <= remaining <= NEAR_S:
            wait = min(wait, NEAR_REFRESH_S)
    return wait
