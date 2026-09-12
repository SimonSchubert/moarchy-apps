# moarchy-apps

The apps for a Linux phone that Android has and Linux does not.

`docs/android-gaps.md` in moarchy-store lists thirteen of them: things with a
good, translated, maintained implementation on F-Droid and no Linux answer in
the aarch64 repos, the AUR or Flathub. This is where they get written.

| app | what it is | state |
|---|---|---|
| [habits](apps/habits) | Habit tracking: a tap a day, a streak, sixteen weeks of history | first cut |

Gap #9 on that list — Loop Habit Tracker has 72 translations and Linux has
nothing; `francis`, the nearest thing in the catalogue, is a pomodoro timer.

## Why one repo

Because there are a dozen of these coming, and the alternative is a dozen
repositories that each need their own CI, their own container, their own
`ruff.toml`, and their own copy of the code that reads an Omarchy theme — which
had already been copied three times before this repo existed, at 440, 360 and
287 lines, differing by four.

The usual objection to a monorepo is that it forces one version number across
unrelated apps. It does not. `git archive` takes a **subtree at a tag**:

```sh
git archive --prefix=moarchy-habits-0.1.0/ habits-v0.1.0:apps/habits
```

So each app keeps its own tag, its own version, its own PKGBUILD and its own
pacman package. `packaging/release.sh` assembles the release tarball from two
subtrees of one tag — the app, and the shared code it uses — which makes each
tarball self-contained: no submodule, no runtime dependency between apps, and a
checksum that still names exact code.

## Layout

```
shared/moarchy_ui/     the half of "theme" that is the same in every app
apps/<name>/           one app: its package, data, tests, demo, PKGBUILD
packaging/release.sh   tag -> per-app tarball + sha256
packaging/repo-add.sh  built packages -> a signed [moarchy] pacman repo
scripts/check.sh       lint, tests, and a real run at 360x720
docker/Dockerfile.dev  the GNOME stack the phone has and a Mac does not
```

Shared code is **vendored into each package at build time**, not shipped as its
own pacman package. moarchy-store reports what an app costs in packages and
megabytes onto a stock image, and a second package for two hundred lines of
palette arithmetic is a cost with nothing behind it. One source copy here, many
self-contained packages there.

## The part that is not writing the app

An app nobody can install is a hobby. moarchy-store installs through a helper
that execs `pacman -S` against an allowlist it reads from a root-owned, signed
`catalogue.toml`. An AUR package is in no sync database, so the helper cannot
install one **at all** — which is why `moarchy-keep` sits in that repo's
`sweep/verdicts.toml` as *"AUR only, and ours"*, deferred from a store we wrote.

The standing answer recorded there is *"if an AUR app matters, package it for
the repos rather than weaken the allowlist"*. `packaging/repo-add.sh` is that,
done literally: a signed binary repo **is** a pacman sync database, so

- the helper works unchanged — it never asks which repo a package came from,
  only whether the name is in the catalogue;
- the allowlist is untouched, so the security property the helper exists to
  provide stays exactly as narrow as it was;
- packages carry a signature from the same key that signs the catalogue, which
  is better provenance than the AUR offers.

What changes is one stanza in the image's `/etc/pacman.conf`, with the key
pinned — a decision made once, deliberately, rather than a hole.

```
[moarchy]
SigLevel = Required TrustedOnly
Server = https://simonschubert.github.io/moarchy-apps/aarch64
```

That single change is what makes every app in this repo listable, and it
retires the "AUR only" verdict for `moarchy-keep` and `moarchy-airwaves` too.

## Working on it

```sh
scripts/check.sh            # every app
scripts/check.sh habits     # one
```

ruff, then the storage tests, then a real run on a virtual screen that fails on
any GTK warning. The last one is the one that matters: a layout error is not an
exception — the app starts, the window appears, and one widget is the wrong size,
with a single line on stderr as the only sign. It is also how the first cut of
Habits was caught calling a method that had been attached to the wrong class.

There is no GTK on a Mac, so the UI checks want the container:

```sh
docker build --platform linux/arm64 -f docker/Dockerfile.dev -t moarchy-apps-dev .
docker run --rm --platform linux/arm64 -v "$PWD:/src" -w /src moarchy-apps-dev scripts/check.sh
```

It runs the Arch Linux ARM GNOME stack natively on Apple Silicon, with
`GSK_RENDERER=cairo` — which is what a Mali-400 falls back to as well, so what
is drawn there is what the phone draws.

## Adding an app

1. `apps/<name>/` with `moarchy_<name>/`, `data/`, `tests/`, `demo.py`,
   `launcher`, `PKGBUILD`, `README.md`.
2. Import the palette from `moarchy_ui.theme`; keep only what is yours.
3. `scripts/check.sh <name>` green, including the real run.
4. Tag `<name>-v<version>`, `packaging/release.sh <name> <version>`, put the
   printed sha256 in the PKGBUILD, upload the tarball as the release asset.
5. `packaging/repo-add.sh`, publish, then add the row to moarchy-store's
   `catalogue.toml` — and measure it in the VM first, like any other entry.

## Licence

MIT.
