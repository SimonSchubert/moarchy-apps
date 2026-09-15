# moarchy-apps

The apps for a Linux phone that Android has and Linux does not.

`docs/android-gaps.md` in moarchy-store lists thirteen of them: things with a
good, translated, maintained implementation on F-Droid and no Linux answer in
the aarch64 repos, the AUR or Flathub. This is where they get written.

| app | what it is | state |
|---|---|---|
| [keep](apps/keep) | Notes and checklists, in the shape of Google Keep | v0.1.1 |
| [habits](apps/habits) | Habit tracking: a tap a day, a streak, sixteen weeks of history | v0.1.2 |
| [reversi](apps/reversi) | Reversi: a board drawn for 360px, an opponent on a clock | v0.1.0 |
| [chess](apps/chess) | Chess: two taps a move, an opponent in the app, no second package | v0.1.0 |
| [queens](apps/queens) | *Packaging only:* sidhant947's crown-placement puzzle, and the Linux runner it does not ship | 1.0.8 |
| [tictactoe](apps/tictactoe) | Noughts and crosses: the game solved at startup, then told to err | v0.1.0 |
| [solitaire](apps/solitaire) | Klondike: one tap a move, and an app that says when a deal is lost | v0.1.0 |
| [pegsolitaire](apps/pegsolitaire) | Peg solitaire: nine figures, all solvable, and a hint that is a proof | v0.1.0 |
| [minesweeper](apps/minesweeper) | Minesweeper: a portrait board, a latching flag, and a clock that stops | v0.1.0 |
| [mill](apps/mill) | Nine Men's Morris: three squares, an opponent on a clock, and the rule everybody forgets | v0.1.0 |
| [fiveletters](apps/fiveletters) | A five-letter word a day: its own keyboard, and a mark as well as a colour | v0.1.0 |
| [breakout](apps/breakout) | Breakout: a bat that follows your thumb, and a clock that stops with the window | v0.1.0 |
| [vitals](apps/vitals) | A task manager: processor, memory, tasks and network, read from /proc | v0.1.0 |
| [puzzle-games](apps/puzzle-games) | *Packaging only:* sidhant947's suite of 300+ small puzzles, minus the titlebar | 1.1.4 |
| [coins](apps/coins) | A coin tracker: the top hundred by market cap, and the ones you star | v0.1.1 |
| [food](apps/food) | Point the camera at a barcode: nutrition facts from Open Food Facts | v0.1.0 |
| [launches](apps/launches) | Upcoming rockets: a countdown, a pad, and the ones you star | v0.1.0 |
| [calculator](plugins/org.moarchy.calculator) | *Shell plugin only:* the four operations, and arithmetic that counts in tens | v0.1.0 |
| [weather](plugins/org.moarchy.weather) | *Shell plugin only:* now, the next day and the week, for the places you named | v0.1.0 |
| [calendar](plugins/org.moarchy.calendar) | *Shell plugin only:* the month, the day under it, and what is next | v0.1.0 |
| [clock](plugins/org.moarchy.clock) | *Shell plugin only:* an alarm that rings late and says so, a stopwatch and a timer | v0.1.0 |

Food is the Open Food Facts row on that list: barcode to nutrition, and Linux
has `qrca` and `decoder`, which read a code and do not say what the packet is.
There is no typed entry. A camera the phone does not have is an empty state,
which is the honest version of requiring one.

Launches is not on that list. Space Launch Now is the F-Droid analogue and it
did not survive the filter; the probe the list describes still comes back
empty, the same way Coins' did. One GET of Launch Library 2, a countdown that
stops lying when the NET is a quarter, and no livestream.

Habits is gap #9 on that list — Loop has 72 translations and Linux has nothing;
`francis`, the nearest thing in the catalogue, is a pomodoro timer. Keep came in
from its own repository with its history, and is the reason the shared half of
`theme.py` exists.

Queens is the odd row: nobody here wrote it. It is a Flutter app by sidhant947
that targets Android, runs on aarch64 Linux without a line of its code changing,
and has no `linux/` directory because `flutter create` generates one on demand.
That generated runner is not in upstream's repository, changes with the SDK, and
is exactly where a phone's one change has to live — so it is committed in
`apps/queens` and the PKGBUILD builds upstream's code against it. A fork would
carry their whole history to hold ten files; this carries the ten files.
`apps/queens/README.md` says what the change is and why it is an environment
variable rather than an `#ifdef`.

Puzzle is the same arrangement and a smaller one. Upstream commits `linux/`
there — alongside `snap/`, `macos/` and `windows/` — so the Linux target already
works and the whole delta is one patch against a real, versioned file. Queens
needed the runner carried; Puzzle needed a branch. Both are upstream as
[Queens#15](https://github.com/sidhant947/Queens/pull/15) and
[Puzzle#168](https://github.com/sidhant947/Puzzle/pull/168), and if they land
these directories keep only their PKGBUILDs.

Reversi and Chess are **not** on that list, and both READMEs say so in as many
words: GNOME has shipped Iagno and Chess for twenty years and they are
`gnome-reversi` and `gnome-chess` in `extra`. They are here because the list
measures what Linux lacks, and a phone lacks things the list does not ask about
— a board drawn for 360px, an opponent that answers on a clock rather than at a
depth chosen on a laptop, and a game written to disk on every move because
phones reclaim apps rather than closing them. Chess adds one more: `pacman -Si
gnome-chess` lists `gnuchess` as an *optional* dependency, so the board you
install has nobody in it until you install a second package, and the search here
is in the app. Whether either survives 360px is a question for moarchy-store's
sweep, which exists to score exactly that.

Vitals is the third of those, and the honest version of the argument is in its
README: Linux is not short of system monitors, and moarchy-store's own catalogue
already lists two — `gnome-usage`, and `bottom`, which is there because *btop
does not fit a phone's terminal at 47 columns*. What a phone lacks is the
content of btop with a thumb-sized switcher along the bottom: per-core bars,
network throughput, heat and charge, and a task list that groups a browser's
twenty processes into one row you can end with a tap. It also reads nothing but
`/proc`, so it costs the stock image no package at all beyond the GUI stack that
is already on it.

Coins is the fourth, and it is the one whose README had to go and look. The
gaps list does not ask for a coin tracker — it is drawn from F-Droid filtered by
translation count and screenshots, and no tracker survived that — but the probe
it describes, run by hand against the same three sets, comes back with a
terminal ticker in `extra`, a desktop trading terminal on the AUR, and wallets
on Flathub. Somewhere to *keep* coins is a different and much more dangerous
thing than somewhere to look at what they cost, which is why this one has no
wallet, no portfolio and no amount in it anywhere — and why the only thing it
ever sends is the name of a starred coin that has fallen out of the top hundred.

Calculator is the one row that is not a directory in `apps/`. It has no GTK
half and is not going to get one: it was written as a shell plugin, which is
what a calculator should have been all along. The argument `plugins/` exists to
make is that summoning an app can be `visible = true` on a window the shell
already holds rather than four seconds of starting Python and GTK, and a
calculator is the app that argument is *about* — it is opened for eleven
seconds, several times a day, usually while somebody is holding something else
in their other hand. It is also not a gap, and its README says so in as many
words: `gnome-calculator` is in `extra`, it is adaptive, and it knows more
mathematics than this ever will. What it is not is a keypad whose keys are 62px
with the sum sitting on them and no second screen anywhere. The part worth reading is `Decimal.js`, which is there
because `0.1 + 0.2` in JavaScript is 0.30000000000000004 and a calculator is the
one program on the phone where that is a wrong answer rather than a rounding
detail — Python's half of this repository would reach for `decimal`, and QML has
none, so this is one.

Weather is the second plugin with no app behind it, and it is the first one
here that has to say what it *is not*. moarchy-store's `docs/android-gaps.md`
puts Breezy Weather in tier one — "radar, air quality, pollen, warnings, many
sources" — and names it one of the three worth writing first. This is none of
those five things, so that row stays open. What the same catalogue already has
is `gnome-weather`, listed, featured, and swept as *"Ran at 360x674 and drew
correctly; follows the theme. 1 packages, 0.15 MB"*, with `kweather` beside it.
So the honest version is the calculator's argument again, and the two phone
things here are that it is already running when it is summoned, and that now,
today and the week are one column you scroll rather than three places to
navigate between — the towns live behind the title, because choosing one is
something you do twice a year and reading the sky is something you do at a bus
stop. It also asks nothing about where the phone is: there is no geolocation
and no IP lookup, a place is on the list because somebody typed it, and that
is what makes the whole of its network behaviour a sentence — one request per
town being looked at, four times an hour, while the window is on the screen.

`scripts/qml-shot.sh` arrived with it, and closes something
`plugins/org.moarchy.launches/README.md` had been carrying as a known gap:
there was no screenshot harness for plugins, because `scripts/screenshot.sh`
photographs an X server with `import` and a Quickshell app is a Wayland client.
It runs the plugin under headless sway — the compositor the phone runs — and
takes the picture with `grim`. Same division of labour as the GTK harness:
*what* to photograph is `plugins/<id>/shots.sh`.

Calendar is the third of these with no app behind it, and the first whose
argument is a number. The gaps list has no calendar row because the store
already has one: `gnome-calendar` is in `extra`, catalogued, *featured*, and
swept as fitting — "a seven-column month grid with week numbers at 360px is as
tight as that can be drawn, and it is legible". What the sweep does not measure
is what it costs to put there. On the container these checks run in — Qt,
Quickshell and no GTK at all — `pacman -S gnome-calendar` wants **112
packages**, because a calendar with accounts in it needs
`evolution-data-server`, which is 30 MB installed, brings GTK3 alongside the
GTK4 that is already there, and brings a WebKit to show somebody a Google
consent screen; then `libedataserverui4` brings the *other* WebKit, because it
is built against GTK4 and the first one is not. Two browser engines behind a
month grid, and none of it anybody's fault: that is the price of accounts, and
a fair one if accounts are what is wanted. This is the other thing — one JSON
file, no daemon, nothing on the network, and three screens drawn for 360px
rather than reflowed onto it. Its README lists the four things it does not do
before it says anything it does, because "it does not ring" is the first thing
somebody should know about a calendar.

Clock is the fourth, and it is the one where being a plugin stops being an
argument about startup time and becomes the only arrangement that works.
`"keepLoaded": true` means the plugin host holds the `Item` from the moment the
shell starts, so the timer watching for an alarm runs inside a process that is
already running for the bar and the gestures — with no window anywhere on the
screen. A GTK app in `apps/` had two shapes available to it and both are worse:
an alarm that rings only while somebody is looking at the app, or a second
package holding a systemd service, with the alarms then living in a process the
app cannot see. `gnome-clocks` is in `extra` and this is not a gap either, and
its README says so before it says anything else — along with the 73 packages
and 60 MB that `pacman -S gnome-clocks` wants on a container with no GTK on it,
five of them a geolocation stack down to `libmm-glib`, so that a clock can ask
the modem where it is. That is the price of the world-clock page, and it is the
page this app does not have. What that README says *next*
is the part worth reading: nothing a user process can do will wake a suspended
phone — `WakeSystem=true` is root's and so is `rtcwake` — so an alarm that came
due while the phone was off rings when it comes back and says *4 minutes late*,
and past an hour does not ring at all and says it went by instead. Ringing at
ten for a seven o'clock alarm is not a late alarm, it is a confusing one. It is
also the first app here to need something back from the shared kit:
`shared/qs_ui/Icon.qml` now takes a name that is already a path, because
Adwaita has an alarm clock and has neither a stopwatch nor an hourglass.

The two share everything that is not the rules — the board is one cairo drawing
area in both, for the same argument about sixty-four widgets, and the clock on
the opponent is the same clock. What they do not share is code: two hundred
lines of near-identical widget would be a third place for the palette to live,
and the thing this repo exists to stop is the palette living in four places. The
shared half is `shared/moarchy_ui`, and it stays the half that is genuinely the
same.

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
shared/qs_ui/          the same half in QML, vendored into each plugin as ui/
apps/<name>/           one app: its package, data, tests, demo, shots, PKGBUILD
plugins/<id>/          one shell plugin: manifest, QML, tests, shots, installer
packaging/release.sh   tag -> per-app tarball + sha256
packaging/repo-add.sh  built packages -> a signed [moarchy-apps] pacman repo
packaging/publish-pages.sh    that repo -> the gh-pages branch it is served from
scripts/check.sh       lint, tests, and a real run at 360x720
scripts/screenshot.sh  the photo harness; apps/<name>/shots.sh says what to shoot
scripts/package.sh     build one app's package from the working tree
scripts/text-input-check.sh   does the app raise the on-screen keyboard?
scripts/qml-check.sh   a plugin's check: qmllint, its tests, a real quickshell
scripts/qml-shot.sh    a plugin's photo harness, under the compositor the phone
                       runs; plugins/<id>/shots.sh says what to shoot
docker/Dockerfile.dev  the GNOME stack the phone has and a Mac does not
docker/Dockerfile.qml  the Qt and Quickshell stack, for the two above
docs/publishing.md     the three channels every app ships in, and what is
                       in which of them today
```

Every harness takes the app as its first argument. The only thing that differs
between photographing a notes app and a habit tracker is *which* screens, so
that list -- and only that list -- lives in the app, as `shots.sh`.

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
- packages carry a detached signature from a key pinned in the image's own
  keyring, which is better provenance than the AUR offers — the AUR ships no
  package signatures at all, because it ships no packages.

What changes is one stanza in the image's `/etc/pacman.conf`, with the key
pinned — a decision made once, deliberately, rather than a hole.

```
[moarchy-apps]
SigLevel = Required TrustedOnly
Server = https://simonschubert.github.io/moarchy-apps/aarch64
```

...and the key that signs it, which is the half that makes `TrustedOnly` mean
anything:

```sh
curl -O https://simonschubert.github.io/moarchy-apps/aarch64/moarchy-apps.gpg
sudo pacman-key --add moarchy-apps.gpg
sudo pacman-key --lsign-key 3CA83612E7F3108F442006B418305B893569BAD3
```

The section is `[moarchy-apps]` and not `[moarchy]` because the distro already
owns that name: a phone's `/etc/pacman.conf` carries `[moarchy]` pointing at
`github.com/SimonSchubert/moarchy/releases/download/repo`, and pacman section
names are unique — the stanza these instructions used to give could not be added
to an image at all. Nor is the name cosmetic. pacman fetches
`<Server>/<section>.db`, so the section name *is* the filename on the far end,
and a repo published under one name cannot be mounted under another. `REPO=`
overrides it in both packaging scripts and now defaults to `moarchy-apps`, so
the database and the stanza cannot drift apart by way of a forgotten variable.

That single change is what makes every app in this repo listable, and it
retires the "AUR only" verdict for `moarchy-keep` too.

It does not retire the AUR. The argument above is about the channel the *store*
installs from, and the AUR was never aimed at the phone — it is where an Arch
user looks for a GTK4 app drawn at 360px, which is a shape they have no other
source for. Both, then, for every app: one PKGBUILD per app pinning one release
tarball by checksum, so the two channels install the same bytes from the same
tag and cannot drift. [`docs/publishing.md`](docs/publishing.md) says which apps
have actually reached which.

The repo is live and holds all thirteen apps at their released versions. It is
built in two halves, because the two tools it needs are on different machines:

```sh
packaging/repo-add.sh packages/*.pkg.tar.*   # in the Arch container, for repo-add
packaging/publish-pages.sh                   # here, where the signing key is
git push origin gh-pages
```

`SigLevel = Required TrustedOnly` is checked rather than assumed: a real pacman
in a clean container, pointed at the published URL with nothing but that key
trusted, syncs the database and installs `moarchy-chess` with
`Validated By: Signature`.

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

**The container is also the authority on lint.** It carries a newer ruff than a
Mac's Homebrew usually does, the two disagree in both directions — rules that
did not exist in the older one, and `# noqa` directives the newer one strips as
unused — and `check.sh` lints `shared`, `apps` and `scripts` for *every* app it
is asked about. So one file the container's ruff dislikes fails the checks for
every app in the repository, including apps nobody has touched. Run the lint
where the checks run, and prefer code that neither version has an opinion about
to a directive that satisfies only one of them.

## Adding an app

1. `apps/<name>/` with `moarchy_<name>/`, `data/`, `tests/`, `demo.py`,
   `launcher`, `PKGBUILD`, `README.md`.
2. Import the palette from `moarchy_ui.theme`; keep only what is yours.
3. `scripts/check.sh <name>` green, including the real run.
4. Tag `<name>-v<version>`, `packaging/release.sh <name> <version>`, put the
   printed sha256 in the PKGBUILD, upload the tarball as the release asset.
5. Push the PKGBUILD and a regenerated `.SRCINFO` to the AUR.
6. `packaging/repo-add.sh`, `packaging/publish-pages.sh`, push `gh-pages`.
7. Add the row to moarchy-store's `catalogue.toml` — and measure it in the VM
   first, like any other entry.

Steps 5 to 7 are three channels and not a choice between them: the AUR is for
everyone not running our image, `[moarchy-apps]` is the only one the store's
helper can install from, and the catalogue is how anybody finds it. `git grep`
will not tell you which of them an app has actually reached, so
[`docs/publishing.md`](docs/publishing.md) holds that table, the order the
scripts run in, and the four gaps that are structural rather than unfinished.

## Licence

MIT.
