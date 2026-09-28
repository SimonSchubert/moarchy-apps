#!/usr/bin/python3
"""Put the recorded answers in front of Video Library, and a library beside them.

dev/capture.py wrote dev/fixture.json: what Odysee said, by the key Video Library
asks with. This copies it into the data folder, where the app reads it when
it runs with MOARCHY_VIDEO_LIBRARY_OFFLINE, and writes a library.json made of the
same claims -- the channels capture.py chose to follow, three videos saved,
four played -- so every tab has something on it and no socket is opened.

    MOARCHY_VIDEO_LIBRARY_DIR=/tmp/video-library python3 apps/video-library/dev/demo.py
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def channel(c: dict) -> dict:
    v = c.get("value") or {}
    return {
        "id": c["claim_id"], "name": c.get("name", ""), "title": v.get("title") or c.get("name", ""),
        "thumb": (v.get("thumbnail") or {}).get("url", ""), "cover": (v.get("cover") or {}).get("url", ""),
        "description": v.get("description", ""), "count": (c.get("meta") or {}).get("claims_in_channel", 0),
        "url": c.get("canonical_url", ""),
    }


def video(c: dict, played: int = 0) -> dict:
    v = c["value"]
    media = v.get("video") or v.get("audio") or {}
    out = {
        "id": c["claim_id"], "name": c["name"], "title": v.get("title") or c["name"],
        "description": v.get("description", ""), "thumb": (v.get("thumbnail") or {}).get("url", ""),
        "kind": v.get("stream_type", "video"), "media": v["source"].get("media_type", ""),
        "size": float(v["source"].get("size", 0) or 0), "duration": media.get("duration", 0),
        "width": (v.get("video") or {}).get("width", 0), "height": (v.get("video") or {}).get("height", 0),
        "released": float(v.get("release_time") or (c.get("meta") or {}).get("creation_timestamp") or 0),
        "tags": [t for t in v.get("tags", []) if not t.startswith("c:")][:16], "license": v.get("license", ""),
        "languages": v.get("languages", []), "sd": v["source"]["sd_hash"][:6], "url": c.get("canonical_url", ""),
        "paid": False, "members": False,
        "channel": channel(c["signing_channel"]) if c.get("signing_channel") else None,
    }
    if played:
        out["playedAt"] = played
    return out


def main() -> int:
    dest = Path(os.environ.get("MOARCHY_VIDEO_LIBRARY_DIR") or
                Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "moarchy-video-library")
    src = HERE / "fixture.json"
    if not src.exists():
        print("no dev/fixture.json -- run dev/capture.py", file=sys.stderr)
        return 1
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy(src, dest / "fixture.json")
    fx = json.loads(src.read_text())
    now = fx["NOW"]

    seen: dict[str, dict] = {}
    for key, ans in fx.items():
        if isinstance(ans, dict) and "result" in ans:
            for c in ans["result"]["items"]:
                if c.get("signing_channel"):
                    seen.setdefault(c["signing_channel"]["claim_id"], c["signing_channel"])
    follows = [channel(seen[i]) for i in fx["FOLLOWS"] if i in seen]
    tech = [c for c in fx["home:tech:1"]["result"]["items"] if c.get("value_type") == "stream"]
    featured = [c for c in fx["home:featured:1"]["result"]["items"] if c.get("value_type") == "stream"]
    saved = [video(c) for c in tech[2:5]]
    history = [video(c, now - 3600 * (i + 1) * 5) for i, c in enumerate(featured[:4])]

    (dest / "library.json").write_text(json.dumps(
        {"version": 1, "follows": follows, "saved": saved, "history": history}, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
