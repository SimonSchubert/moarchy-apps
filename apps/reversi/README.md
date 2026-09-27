# moarchy-reversi

Reversi for a Linux phone: an eight by eight board that fits a 360px screen, an
opponent that answers inside a second on a slow CPU, and a game that survives
being killed.

<p align="center">
  <img src="docs/screenshots/phone.png" width="30%" alt="A game in progress: score boxes reading 14 to 16, a green board of black and white discs with small dots marking the squares the player may play, the last move outlined, and Undo and New game along the bottom">
  <img src="docs/screenshots/phone-newgame.png" width="30%" alt="The new-game sheet: against the computer, difficulty Medium, you play dark">
  <img src="docs/screenshots/phone-record.png" width="30%" alt="The record: 19 played, 10 won, best win +24, and a row per difficulty with win percentages">
</p>
<p align="center">
  <img src="docs/screenshots/desktop-over.png" width="92%" alt="A finished game on a desktop under catppuccin-latte: the board with its files and ranks on the left, and beside it the score 43 to 20, You win, the buttons and the record">
</p>

<p align="center"><em>360×720, and a desktop window. One app: below 720 px it
lays out as a phone app, above it the record sits beside the board. The felt is
not the app's own green — it is the active Omarchy theme's, and a theme switch
repaints it while the game is on the screen.</em></p>

A Quickshell app. Inside the Omarchy shell it is a panel the shell keeps
loaded, so opening it is showing a window rather than starting a process; on
any other Quickshell desktop `moarchy-reversi` runs it as its own. 0.1.0 was a
GTK4/libadwaita app, and a game left in it is the game found here: the file is
the same.

## This one is not a gap

Every other app in this repo answers a row in moarchy-store's
`docs/android-gaps.md` — something with a good implementation on F-Droid and no
Linux answer anywhere. Reversi is not one of those. GNOME has shipped Iagno for
twenty years, it is `gnome-reversi` in `extra`, and it is a better-looking
program than this one.

What it is not is a phone app, and the gap this fills is that one:

- **It is drawn for 360px.** Eight squares of 43px across the short edge, with
  the board, the score and the status as one block, and every control that
  belongs to the game in a bar along the bottom where a thumb already is.
- **The opponent is on a clock, not on a depth.** On a phone the question is
  never "how deep" but "how long", and those are the same question only on the
  machine you tuned it on.
- **It expects to be killed.** Phones do not close apps, they reclaim them. The
  game is written to the file on every move and picked up mid-search on the way
  back in.
- **It is the phone's colours.** The board is the theme's green, and a theme
  change repaints it in place.

Whether Iagno is usable at 360px is a question for moarchy-store's sweep, which
scores packages on exactly that and is the right place for the answer. This is
not an argument that it is not — it is an app written to a different brief.

## What it does

- **Tap a square to play it.** The squares you may play are dotted, because a
  touch screen is not a place to find out by being refused
- **The discs turn over as a wave**, out from the one you played, edge-on at
  the halfway point like a real disc in a hand. It is the whole reward of the
  move and it costs one property per disc
- **On a desktop** the board has its files and ranks, the record sits beside
  it, and the arrow keys move over the board with Enter to play
- **Three levels**, and the easy one genuinely errs rather than being a strong
  opponent with less to think with
- **Two players on one phone**, passing it across a table, with no computer and
  nothing recorded
- **Undo gives you your turn back** — the computer's reply and your move, not
  one ply — because the misplaced tap is the ordinary case on a bus
- **A pass is handled and announced.** A side with no move does not get a board
  with no hints on it and a wait for a tap that cannot come
- **A record** of games against the computer, by difficulty
- **Everything local.** One JSON file, no account, no network code in the app

## The theme's colours

<p align="center">
  <img src="docs/screenshots/desktop-tokyo.png" width="70%" alt="The same board under the tokyo-night theme: a deep olive felt on a near-black window, with black and white discs">
</p>

The same game under `tokyo-night`. The felt is that theme's green mixed into
that theme's background, the grid is a darker shade of the felt, and the
outline on the last move is the theme's accent — so `omarchy-theme-set`
repaints the board while the game is on the screen, the way it repaints the
bar. Without an Omarchy theme it follows the desktop's light or dark, and
Settings can pin either.

The discs are the one thing that does not become a hue of the theme. Two
theme colours is the kind of theming that looks good in a screenshot and fails
in daylight, for the eight percent of men who cannot tell the popular pair
apart, and at 43px. Dark against light survives all three, so the discs take a
tint from the theme and keep their contrast.

## The opponent

It is alpha-beta over bitboards, and both halves of that are about the phone.

**A position is two 64-bit boards**, one bit per square per colour -- each a
pair of 32-bit halves, because JavaScript's bitwise operators are 32-bit
(`Bits.js`) -- so finding every legal move is a handful of shifts and masks
rather than a walk of 64 squares by 8 directions by 7 steps. A search is worth as
many positions a second as the rules can be applied, and on an A53 that is the
difference between an opponent worth beating and one that is not.

**The depth is not decided in advance.** Every level names a number of seconds
and a ceiling, and the search deepens a ply at a time until one of them runs
out. The same "Hard" is a six-ply opponent on a laptop and a four-ply one on a
PinePhone, and neither leaves somebody holding a phone that has stopped
answering. A fixed depth would have to be chosen for the slowest device and
would then be the strength everywhere.

**The last dozen squares are played out exactly** rather than evaluated — but
only by Hard. An easy opponent that plays the endgame perfectly is easy right up
until the part of the game that decides it, which feels like being cheated
rather than beaten.

**The search is on its own thread.** `search.js` runs in a WorkerScript, so
the discs keep turning while the computer thinks, and it starts a beat after
your move lands rather than on top of it. A worker cannot be interrupted, so
every answer carries the generation of the board it was asked about, and one
for a board that has since been taken back, restarted or closed is dropped.
Nothing is searched while the window is shut.

The rules (`Reversi.js`) and the opponent (`Ai.js`) are the same code the
worker runs and the tests read, and they were checked position by position
against 0.1.0's Python. `tests/tst_levels.qml` plays a four-ply Hard against
Easy from both sides and fails if the levels stop being ordered by strength.

## The file

`~/.local/share/moarchy-reversi/reversi.json`, or `$MOARCHY_REVERSI_DIR` if set.

What is stored is the **move list**, not the board:

```json
{
 "schema": 1,
 "game": {"mode": "solo", "level": "medium", "human": "dark",
          "finished": false, "moves": [19, 34, 45, 20, 26, 11]},
 "stats": {"medium": {"played": 9, "won": 4, "lost": 5, "drawn": 0, "best": 20}}
}
```

Sixty small integers replay to exactly one position in microseconds, and that
has a property a stored board cannot have: **a file that has been truncated,
edited or half-written cannot describe a board that legal play could not reach,
because loading it is playing it.** A move that will not play is where the file
stops being a game, and the rest of it goes.

Writes go through a temp file and a rename, on every move rather than on a
timer: a move here is seconds of thinking apart at the very least, and on a
phone the app is not closed, it is killed. A file that will not parse is moved
aside as `reversi.broken-<time>.json` before anything is written over it.

## Running it

```sh
quickshell -p apps/reversi/shell.qml
```

With a game in progress rather than an opening:

```sh
export MOARCHY_REVERSI_DIR=$(mktemp -d)
python3 apps/reversi/dev/demo.py          # 26 plies in, you to move
python3 apps/reversi/dev/demo.py over     # ...or a finished game, passes and all
quickshell -p apps/reversi/shell.qml
```

The fixture is a game 0.1.0's own opponent played, not scattered discs: a
hand-placed board is the app telling a lie about its own rules, and anyone who
knows the game will see it.

## Checks

```sh
docker run --rm -v "$PWD:/src" -w /src moarchy-qml scripts/app-check.sh reversi
docker run --rm -v "$PWD:/src" -w /src moarchy-qml scripts/app-shot.sh reversi
```

The first is qmllint, the rules, the opponent and the file (`tests/`, the
cases 0.1.0's Python tests had), and a real run that fails on any QML warning.
The second photographs `dev/shots` at a phone's size and a desktop's.

On a desktop: the arrow keys move over the board and Enter or Space plays the
square, `u` undoes, `n` starts a new game.

| variable | what it does |
|---|---|
| `MOARCHY_REVERSI_DIR` | where the game lives |
| `MOARCHY_QUIT_AFTER` | quit after N seconds, for headless runs |
| `MOARCHY_REVERSI_PAGE` | open straight into `record`, for the screenshots |
| `MOARCHY_REVERSI_NEW` | open with the new-game sheet up |
| `MOARCHY_REVERSI_SETTINGS` | open on Settings |

The IPC target `reversi` answers `play <square>` (`play d3`), `board`, `score`
and `settled`, for a script that wants to drive a game.

## Licence

MIT.
