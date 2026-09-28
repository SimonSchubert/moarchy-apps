#!/usr/bin/python3
"""Record what Open Library answers, under the keys Books asks with, for the shots.

A catalogue photographs badly against the real thing: Trending is different
every day and a cover can change under a work. So this asks the questions
Books asks once, trims each answer to the fields OpenLibrary.js reads, and
writes

  dev/fixture.json   the answers, by request key (Requests.qml offline), and
                     the books dev/demo.py puts on the shelves, as "lib:<id>"
  dev/.covers/       the pictures, by number (MOARCHY_BOOKS_COVERS):
                     <cover>-M.jpg for every book, -L and -S for the ones a
                     shot opens, a<photo>.jpg for an author

dev/demo.py copies the fixture in front of each shot, and dev/shots pins the
clock to NOW in the fixture, so "this year" is the same year every time.

    python3 apps/books/dev/capture.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
BASE = "https://openlibrary.org"
COVERS = "https://covers.openlibrary.org"
AGENT = "moarchy-books/0.1.0 (+https://github.com/SimonSchubert/moarchy-apps)"
PAGE = 24
FIELDS = ("key,title,subtitle,author_name,author_key,cover_i,first_publish_year,edition_count,"
          "ratings_average,ratings_count,number_of_pages_median,want_to_read_count,already_read_count")
AUTHOR_FIELDS = "key,name,birth_date,death_date,top_work,work_count"
SUBJECTS = ["fantasy", "science_fiction", "mystery_and_detective_stories", "historical_fiction",
            "classic_literature", "horror", "romance", "young_adult_fiction", "biography", "history",
            "science", "philosophy", "psychology", "poetry", "cooking"]
SEARCH_BOOKS = ["le guin"]
SEARCH_AUTHORS = ["tolkien"]
# The pages the shots open: a book, and an author.
OPEN_WORKS = ["OL893414W"]           # Dune
OPEN_AUTHORS = ["OL79034A"]          # Frank Herbert
# The reading list dev/demo.py writes, found by title and author.
LIBRARY = {
    "reading": [("dune", "frank herbert"), ("the left hand of darkness", "le guin")],
    "want": [("project hail mary", "andy weir"), ("piranesi", "susanna clarke"),
             ("the name of the wind", "patrick rothfuss"), ("the remains of the day", "ishiguro"),
             ("sapiens", "harari"), ("the dispossessed", "le guin")],
    "read": [("the hobbit", "tolkien"), ("nineteen eighty-four", "orwell"), ("the martian", "andy weir"),
             ("frankenstein", "mary shelley"), ("fahrenheit 451", "bradbury"), ("neuromancer", "gibson"),
             ("pride and prejudice", "austen"), ("the road", "cormac mccarthy"),
             ("a wizard of earthsea", "le guin")],
}


def curl(url: str) -> object:
    for attempt in range(4):
        out = subprocess.run(["curl", "-sS", "-L", "--compressed", "--max-time", "60",
                              "-H", f"User-Agent: {AGENT}", url], capture_output=True)
        if out.returncode == 0:
            try:
                return json.loads(out.stdout)
            except ValueError:
                pass
        time.sleep(2 + attempt * 3)
    raise SystemExit(f"no answer from {url}")


def search(params: dict) -> dict:
    return curl(BASE + "/search.json?" + urllib.parse.urlencode(params))


def trim_docs(d: dict, fields: str) -> dict:
    keep = fields.split(",")
    docs = d.get("docs") if "docs" in d else d.get("works", [])
    out = [{k: x[k] for k in keep + ["cover_id"] if k in x} for x in docs]
    return {"numFound": d.get("numFound", 0), "docs": out}


def main() -> int:
    fx: dict[str, object] = {"NOW": int(time.time())}

    print("trending, and fifteen subjects", file=sys.stderr)
    fx["trending:1"] = trim_docs(curl(f"{BASE}/trending/weekly.json?limit={PAGE}&page=1"), FIELDS)
    for s in SUBJECTS:
        fx[f"subject:{s}:1"] = trim_docs(search({"q": f"subject_key:{s}", "sort": "readinglog",
                                                 "fields": FIELDS, "limit": PAGE, "page": 1}), FIELDS)
    for q in SEARCH_BOOKS:
        fx[f"search:books:{q}:1"] = trim_docs(search({"q": q, "fields": FIELDS, "limit": PAGE, "page": 1}), FIELDS)
    for q in SEARCH_AUTHORS:
        a = curl(BASE + "/search/authors.json?" + urllib.parse.urlencode(
            {"q": q, "sort": "work_count desc", "fields": AUTHOR_FIELDS, "limit": PAGE, "offset": 0}))
        fx[f"search:authors:{q}:1"] = {"numFound": a.get("numFound", 0), "docs": a.get("docs", [])}

    print("the reading list", file=sys.stderr)
    for shelf, wants in LIBRARY.items():
        for title, author in wants:
            d = search({"title": title, "author": author, "fields": FIELDS, "limit": 1, "sort": "readinglog"})
            if d.get("docs"):
                doc = d["docs"][0]
                fx["lib:" + doc["key"].split("/")[-1]] = {"shelf": shelf, "doc": doc}

    print("book and author pages", file=sys.stderr)
    works = list(OPEN_WORKS) + [k[4:] for k in fx if k.startswith("lib:")]
    for w in dict.fromkeys(works):
        full = curl(f"{BASE}/works/{w}.json")
        fx[f"work:{w}"] = {k: full[k] for k in ("key", "title", "subtitle", "covers", "authors", "description",
                                                "subjects", "subject_places", "subject_people",
                                                "first_publish_date", "excerpts") if k in full}
        fx[f"ratings:{w}"] = curl(f"{BASE}/works/{w}/ratings.json")
        fx[f"shelves:{w}"] = curl(f"{BASE}/works/{w}/bookshelves.json")
    authors = set(OPEN_AUTHORS)
    for key, ans in list(fx.items()):
        if key.startswith("work:"):
            for a in ans.get("authors", []):
                k = (a.get("author") or a).get("key", "")
                if k:
                    authors.add(k.split("/")[-1])
    for a in sorted(authors):
        full = curl(f"{BASE}/authors/{a}.json")
        fx[f"author:{a}"] = {k: full[k] for k in ("key", "name", "personal_name", "bio", "birth_date",
                                                  "death_date", "photos", "links", "wikipedia") if k in full}
    for a in OPEN_AUTHORS:
        fx[f"by:{a}:1"] = trim_docs(search({"author": a, "sort": "readinglog", "fields": FIELDS,
                                            "limit": PAGE, "page": 1}), FIELDS)

    (HERE / "fixture.json").write_text(json.dumps(fx, separators=(",", ":"), ensure_ascii=False) + "\n")

    print("covers", file=sys.stderr)
    pics: dict[str, str] = {}
    for key, ans in fx.items():
        docs = ans.get("docs", []) if isinstance(ans, dict) else []
        if key.startswith("lib:"):
            docs = [ans["doc"]]
        for d in docs:
            c = d.get("cover_i") or d.get("cover_id")
            if c:
                pics[f"{c}-M.jpg"] = f"{COVERS}/b/id/{c}-M.jpg"
                if key.startswith("lib:"):
                    pics[f"{c}-L.jpg"] = f"{COVERS}/b/id/{c}-L.jpg"
                    pics[f"{c}-S.jpg"] = f"{COVERS}/b/id/{c}-S.jpg"
        if key.startswith("work:"):
            for c in (ans.get("covers") or [])[:1]:
                if c > 0:
                    for size in "SML":
                        pics[f"{c}-{size}.jpg"] = f"{COVERS}/b/id/{c}-{size}.jpg"
        if key.startswith("author:"):
            for p in (ans.get("photos") or [])[:1]:
                if p > 0:
                    pics[f"a{p}.jpg"] = f"{COVERS}/a/id/{p}-L.jpg"
    # The trending doc's cover for a book the shots open, L and S too.
    for key, ans in fx.items():
        for d in ans.get("docs", []) if isinstance(ans, dict) else []:
            if d.get("key", "").split("/")[-1] in OPEN_WORKS and d.get("cover_i"):
                for size in "SL":
                    pics[f"{d['cover_i']}-{size}.jpg"] = f"{COVERS}/b/id/{d['cover_i']}-{size}.jpg"

    out = HERE / ".covers"
    out.mkdir(exist_ok=True)

    def fetch(item: tuple[str, str]) -> None:
        name, url = item
        dest = out / name
        if dest.exists() and dest.stat().st_size > 1000:
            return
        subprocess.run(["curl", "-sS", "-L", "--max-time", "60", "-H", f"User-Agent: {AGENT}",
                        "-o", str(dest), url], check=False)

    with ThreadPoolExecutor(8) as pool:
        list(pool.map(fetch, sorted(pics.items())))
    print(f"{len(fx)} answers, {len(pics)} pictures", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
