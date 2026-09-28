#!/usr/bin/python3
"""Record what Odysee answers, under the keys Video Library asks with, for the shots.

A video browser photographs badly against the real thing: the front page is
different every hour and the pictures are whatever was uploaded today. So this
asks the questions Video Library asks once, trims each claim to the fields Lbry.js
reads, and writes

  dev/fixture.json   the answers, by request key (Requests.qml offline)
  dev/.thumbs/       the pictures, by claim id (MOARCHY_VIDEO_LIBRARY_THUMBS)

dev/demo.py copies the fixture in front of each shot, and dev/shots pins the
clock to NOW in the fixture, so "3 days ago" is three days ago every time.

    python3 apps/video-library/dev/capture.py

It uses curl, as the app does: odysee.com refuses Python's own client.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
import urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROXY = "https://api.na-backend.odysee.com/api/v1/proxy"
LIGHTHOUSE = "https://lighthouse.odysee.tv/search"
HOMEPAGE = "https://odysee.com/$/api/content/v2/get?format=roku"
IMAGES = "https://thumbnails.odycdn.com/card/"
AGENT = "moarchy-video-library/0.1.0 (+https://github.com/SimonSchubert/moarchy-apps)"
PAGE = 24
CATS = ["featured", "tech", "gaming"]
SEARCH = "linux"
NOT_TAGS = ["porn", "porno", "nsfw", "mature", "xxx", "sex", "creampie",
            "blowjob", "handjob", "vagina", "boobs", "big boobs", "big dick",
            "pussy", "cumshot", "anal", "hard fucking", "ass", "fuck", "hentai",
            "c:members-only", "c:unlisted", "c:private"]


def curl(url: str, body: dict | None = None) -> object:
    argv = ["curl", "-sS", "--compressed", "--max-time", "40", "-H", f"User-Agent: {AGENT}"]
    if body is not None:
        argv += ["-H", "Content-Type: application/json", "--data-binary", json.dumps(body)]
    out = subprocess.run(argv + [url], check=True, capture_output=True).stdout
    return json.loads(out)


def rpc(method: str, params: dict) -> dict:
    return curl(PROXY, {"jsonrpc": "2.0", "method": method, "params": params, "id": 1})


def base(page: int = 1) -> dict:
    return {"page": page, "page_size": PAGE, "claim_type": ["stream"], "has_source": True,
            "no_totals": True, "not_tags": NOT_TAGS}


def trim_channel(c: dict | None) -> dict | None:
    if not c or c.get("value_type") != "channel":
        return None
    v = c.get("value") or {}
    return {
        "claim_id": c["claim_id"], "name": c.get("name"), "value_type": "channel",
        "canonical_url": c.get("canonical_url"),
        "meta": {"claims_in_channel": (c.get("meta") or {}).get("claims_in_channel", 0)},
        "value": {k: v[k] for k in ("title", "thumbnail", "cover") if k in v}
        | {"description": (v.get("description") or "")[:600]},
    }


def trim(c: dict) -> dict:
    if c.get("value_type") == "channel":
        return trim_channel(c)
    v = c.get("value") or {}
    keep = {k: v[k] for k in ("title", "thumbnail", "stream_type", "video", "audio", "tags",
                              "release_time", "license", "languages", "fee") if k in v}
    keep["description"] = (v.get("description") or "")[:900]
    src = v.get("source") or {}
    keep["source"] = {k: src[k] for k in ("sd_hash", "media_type", "size") if k in src}
    return {
        "claim_id": c["claim_id"], "name": c.get("name"), "value_type": c.get("value_type"),
        "canonical_url": c.get("canonical_url"), "timestamp": c.get("timestamp"),
        "meta": {"creation_timestamp": (c.get("meta") or {}).get("creation_timestamp")},
        "value": keep, "signing_channel": trim_channel(c.get("signing_channel")),
    }


def trimmed(answer: dict) -> dict:
    items = [trim(i) for i in answer.get("result", {}).get("items", [])]
    return {"jsonrpc": "2.0", "result": {"items": [i for i in items if i]}}


def main() -> int:
    now = int(time.time())
    fixture: dict[str, object] = {"NOW": now}

    home = curl(HOMEPAGE)
    cats = home["data"]["en"]["categories"]
    slim = []
    for c in cats:
        c = {k: c[k] for k in ("name", "label", "channelLimit", "daysOfContent", "order",
                               "sortOrder", "hideByDefault", "channelIds", "excludedChannelIds") if k in c}
        # The shots open five categories; the rest only need to be chips.
        if c["name"] not in CATS and c.get("channelIds"):
            c["channelIds"] = c["channelIds"][:1]
        slim.append(c)
    fixture["homepage"] = {"status": "success", "data": {"en": {"categories": slim}}}

    by = {c["name"]: c for c in cats}
    for name in CATS:
        c = by[name]
        p = base() | {"stream_types": ["video"], "fee_amount": "<=0", "duration": ">60",
                      "release_time": f">{now - int(c.get('daysOfContent', 30)) * 86400}",
                      "order_by": ["release_time"] if c.get("order") == "new" else ["trending_group", "trending_mixed"],
                      "channel_ids": c["channelIds"]}
        if int(c.get("channelLimit", 0) or 0):
            p["limit_claims_per_channel"] = int(c["channelLimit"])
        fixture[f"home:{name}:1"] = trimmed(rpc("claim_search", p))
        print(f"home:{name}", len(fixture[f"home:{name}:1"]["result"]["items"]), file=sys.stderr)

    # Channels: the first few of the front page, followed; each one's uploads.
    featured = fixture["home:featured:1"]["result"]["items"]
    tech = fixture["home:tech:1"]["result"]["items"]
    channels: list[str] = []
    for item in featured[:1] + tech[:6]:
        ch = item.get("signing_channel")
        if ch and ch["claim_id"] not in channels:
            channels.append(ch["claim_id"])
    follows = channels[:5]
    for cid in channels:
        fixture[f"channel:{cid}:1"] = trimmed(rpc("claim_search", base() | {
            "stream_types": ["video", "audio"], "channel_ids": [cid], "order_by": ["release_time"]}))
    fixture["following:1"] = trimmed(rpc("claim_search", base() | {
        "stream_types": ["video", "audio"], "channel_ids": follows, "order_by": ["release_time"]}))
    fixture["FOLLOWS"] = follows

    for kind in ("videos", "channels"):
        q = f"?s={urllib.parse.quote(SEARCH)}&size={PAGE}&from=0&nsfw=false"
        q += "&claimType=channel" if kind == "channels" else "&claimType=file&mediaType=video,audio&free_only=true"
        hits = curl(LIGHTHOUSE + q)
        ids = [h["claimId"] for h in hits]
        fixture[f"lighthouse:{kind}:{SEARCH}:1"] = hits
        fixture[f"claims:{kind}:{SEARCH}:1"] = trimmed(rpc("claim_search", {
            "claim_ids": ids, "page_size": len(ids), "no_totals": True,
            "claim_type": ["channel"] if kind == "channels" else ["stream"]}))

    (HERE / "fixture.json").write_text(json.dumps(fixture, ensure_ascii=False, indent=None) + "\n")

    # The pictures, at the sizes the app asks the CDN for.
    thumbs = HERE / ".thumbs"
    thumbs.mkdir(exist_ok=True)
    want: dict[str, tuple[str, int, int]] = {}
    for key, ans in fixture.items():
        if not isinstance(ans, dict) or "result" not in ans:
            continue
        for c in ans["result"]["items"]:
            v = c.get("value") or {}
            if c.get("value_type") == "channel":
                chans = [c]
            else:
                if (v.get("thumbnail") or {}).get("url"):
                    want[c["claim_id"]] = (v["thumbnail"]["url"], 960, 540)
                chans = [c.get("signing_channel")] if c.get("signing_channel") else []
            for ch in chans:
                cv = ch.get("value") or {}
                if (cv.get("thumbnail") or {}).get("url"):
                    want[ch["claim_id"]] = (cv["thumbnail"]["url"], 192, 192)
                if (cv.get("cover") or {}).get("url"):
                    want[ch["claim_id"] + "-cover"] = (cv["cover"]["url"], 1280, 284)
    for i, (key, (src, w, h)) in enumerate(sorted(want.items())):
        out = thumbs / f"{key}.jpg"
        if out.exists():
            continue
        subprocess.run(["curl", "-sS", "-f", "--max-time", "30", "-o", str(out),
                        f"{IMAGES}s:{w}:{h}/quality:80/plain/{src}"], check=False)
        # A picture that is gone comes back as a page saying so, with a 200.
        if out.exists() and not out.read_bytes()[:3] == b"\xff\xd8\xff":
            out.unlink()

    # A picture the CDN no longer has is a claim with no picture, which is
    # what the app would show for it anyway -- without a failed load per shot.
    gone = {k for k in want if not (thumbs / f"{k}.jpg").exists()}

    def blank(c: dict | None) -> None:
        if not c:
            return
        v = c.get("value") or {}
        if c["claim_id"] in gone:
            v.pop("thumbnail", None)
        if c["claim_id"] + "-cover" in gone:
            v.pop("cover", None)
        blank(c.get("signing_channel"))

    for ans in fixture.values():
        if isinstance(ans, dict) and "result" in ans:
            for c in ans["result"]["items"]:
                blank(c)
    (HERE / "fixture.json").write_text(json.dumps(fixture, ensure_ascii=False, indent=None) + "\n")
    print(f"{len(fixture)} answers, {len(want) - len(gone)} pictures, {len(gone)} gone", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
