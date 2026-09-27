# moarchy-fiveletters

A five-letter word a day, for a Linux phone: a keyboard of its own so the board
is never covered, a mark on every tile as well as a colour, and English only,
which it says rather than pretending otherwise.

<p align="center">
  <img src="docs/screenshots/phone.png" width="30%" alt="Four guesses in: CRANE, SLOTH, WHOMP and VIXEN coloured grey and yellow with a ring in the corner of every yellow tile, SPINE typed in the fifth row, and a QWERTY keyboard below with its keys coloured">
  <img src="docs/screenshots/phone-solved.png" width="30%" alt="The same board solved on the fifth guess: ATTIC in green with a filled dot in the corner of every tile, and Close one, in 5">
  <img src="docs/screenshots/phone-record.png" width="30%" alt="The record: 121 played, 94% solved, a streak of 12, a best of 34, and a bar chart of how many guesses each day took">
</p>
<p align="center">
  <img src="docs/screenshots/desktop-light.png" width="92%" alt="On a desktop: the solved board and a smaller keyboard on the left, and beside them A practice word, Copy result and the record">
</p>

<p align="center"><em>360×720, and a desktop window. One app: below 720 px it
lays out as a phone app, above it the record sits beside the board. The green
and the yellow are the active Omarchy theme's own, and a theme switch repaints
them while the board is on the screen.</em></p>

A Quickshell app. Inside the Omarchy shell it is a panel the shell keeps
loaded; on any other Quickshell desktop `moarchy-fiveletters` runs it as its
own. 0.1.0 was a GTK4/libadwaita app, and it set the same word on the same day
and kept the same file, so a streak carries over.

## The name

It is the game everybody means by Wordle. It is not called that, for the same
reason the board game in this repository is called Reversi and not Othello: the
famous name belongs to somebody — a newspaper in one case and a Japanese
trademark in the other — and the generic one describes the thing perfectly well.

## Its own keyboard

The phone has one already, and using it would mean the on-screen keyboard
sliding up over the bottom two rows of a board that *is the entire game*, plus
autocorrect, a space bar, a number row and a comma, none of which this game has
any use for.

So the app draws twenty-eight keys, and gets three things for it:

- **the board is never covered**, because the keyboard is part of the window
  rather than something that arrives over it;
- **the keys are coloured by what is known about each letter**, which is half of
  how anybody plays this game and is not something a system keyboard can do;
- **there is nothing to type that is not a move.**

It still takes a physical keyboard — letters, Return and Backspace — because
this runs on a desktop too and somebody with one will try.

Three rows of real keys rather than a drawing: ten, then nine indented by
half a key, then seven between an Enter and a Delete worth a key and a half
each. On a desktop the keyboard is still there, smaller, because the colours
on it are half of how anybody plays -- but typing goes to the one the desk has.

## A mark as well as a colour

**The colours are the rules in this game**, and always have been: green means
the letter is in that place, yellow means it is in the word somewhere else, grey
means it is not there. That is exactly the thing Reversi refuses to do with its
discs — and it is allowed here because every version of this game anybody has
played works this way, and a person who cannot separate green from yellow is not
going to be helped by a fourth colour.

What this app does instead is what a tile can carry without becoming a different
game: **a mark of its own in the corner.** A filled dot for a letter in the
right place, an open ring for one in the wrong place, nothing at all for one
that is not in the word. One arc per tile, in the bottom-right corner where a
capital letter never reaches, and the board says which of the three states it is
in by shape as well as by hue.

The green and the yellow are the theme's own rather than the newspaper's, and
the app checks that they are far enough apart to sit next to each other — if a
theme ships a green and a yellow that are nearly the same colour, the yellow
moves to that theme's orange, because side by side is the only way this game
ever uses them. The letter on a tile is whichever of the theme's two extremes is
further from the tile, which is the fix for the first cut of this file: white on
a theme's yellow is a tile nobody can read.

## Two lists, not one

`ANSWERS` in `Lists.js` has 1,510 words that can be the secret. `GUESSES`
has 12,167 that the app will accept as a guess. They answer two different
questions, and a game that used one list for both gets one of them wrong:

- A five-letter string that appears in a dictionary is not the same thing as a
  word a person would guess, and a game whose secret is AALII is a game somebody
  loses for no reason.
- Being told "not a word this app knows" for a real word is the most annoying
  thing this kind of game does, so the guess list is wide.

Both come from [Braincup](https://github.com/SimonSchubert/Braincup), where they
were assembled for the same game — the sources are in `NOTICE.md` — and
they are carried here verbatim so that the two apps stay wrong in the same
places if they are wrong at all. The rules (`Game.js`) are written the same way for the
same reason.

**English only**, and the app says so rather than offering a language picker
with nothing behind it. A word list cannot be translated: every language needs
its own curated words, its own alphabet and its own accent policy, all authored
together.

## Duplicate letters

This is the one rule implementations get wrong, and it is worth the paragraph.

The colouring is two passes. The first marks every letter that is in the right
place and **consumes** that letter from the secret; the second marks a letter
present only while an unconsumed instance of it remains, and absent otherwise.

Guess ALLOY against LOYAL and all five light up, because they are the same five
letters. Guess SPEED against ERASE and only two of the three E-shaped things can
— the secret has two Es. A single pass that asked "is this letter in the word"
would light all three and tell the player something untrue about a word they are
about to spend a guess on.

## One a day

The day's word is a function of the date: the same word for everybody, no
network, no server, nothing to be offline from. It is a multiply-and-add into
the answer list rather than the day number itself, because the list is sorted
and `days % len` would give a week of secrets beginning A, A, A, B, B — a
pattern somebody notices on the fourth day and never unsees.

**The day is checked every time the window opens.** A phone left open
overnight comes back to yesterday's board, and yesterday's board with today's
word on it is a board claiming three letters are green and meaning nothing by it.

When the day's word is done there is **a practice word**, which is never
counted. A streak is a statement about days, and counting practice would turn it
into a statement about how many goes somebody had.

**Copy result** puts the board on the clipboard as coloured squares. It is the
one thing this game is famous for outside itself, and spoiler-free by construction: squares say how a word went
and nothing about what it was.

## The file

`~/.local/share/moarchy-fiveletters/fiveletters.json`, or
`$MOARCHY_FIVELETTERS_DIR`.

```json
{
 "schema": 1,
 "mode": "daily",
 "daily": {"day": "2026-09-12", "guesses": ["CRANE", "SLOTH", "WHOMP", "VIXEN"]},
 "practice": {"seed": 1174338921, "guesses": []},
 "stats": {"played": 121, "won": 114, "streak": 12, "best": 34,
           "spread": [1, 9, 31, 44, 22, 7], "last": "2026-09-11"}
}
```

**Neither secret is in the file.** The day's word is a function of the date and
a practice word is a function of a seed, so both come back from four bytes and
neither is sitting in a text file in somebody's home directory waiting to be
read at two in the morning. It is the same argument Minesweeper's seed makes and
a stronger one here: a minefield is hard to read off a list of taps, and a
five-letter word is not hard to read off anything.

What is stored is the guesses, not the board — so a file that has been
truncated, edited or half-written cannot describe a board that play could not
reach, because loading it is playing it. A word that is not five letters, or is
not in the guess list, is where the file stops being a game.

`last` is a date rather than a counter because of what a streak is: the day you
**skip** ends it as surely as the day you miss, and a counter cannot tell those
apart from simply not having played yet.

## Running it

```sh
quickshell -p apps/fiveletters/shell.qml
```

With a day in progress rather than an empty board:

```sh
export MOARCHY_FIVELETTERS_DIR=$(mktemp -d) MOARCHY_FIVELETTERS_TODAY=2026-09-12
python3 apps/fiveletters/dev/demo.py          # four guesses in
python3 apps/fiveletters/dev/demo.py solved   # ...or the same word, got on the fifth
quickshell -p apps/fiveletters/shell.qml
```

## Checks

```sh
docker run --rm -v "$PWD:/src" -w /src moarchy-qml scripts/app-check.sh fiveletters
docker run --rm -v "$PWD:/src" -w /src moarchy-qml scripts/app-shot.sh fiveletters
```

The first is qmllint, the rules, the lists, the day's word and the file
(`tests/`: 0.1.0's Python cases, plus the words 0.1.0 set on three real days),
and a real run that fails on any QML warning. The second photographs
`dev/shots` at a phone's size and a desktop's.

On a desktop: letters type, Backspace takes one back, Enter guesses, Ctrl+C
copies the result when the day is done.

| variable | what it does |
|---|---|
| `MOARCHY_FIVELETTERS_DIR` | where the game lives |
| `MOARCHY_FIVELETTERS_TODAY` | pin the day, so a screenshot is the same word every time |
| `MOARCHY_QUIT_AFTER` | quit after N seconds, for headless runs |
| `MOARCHY_FIVELETTERS_PAGE` | open straight into `record`, for the screenshots |
| `MOARCHY_FIVELETTERS_TYPED` | open with a word half typed, for the screenshots |

## Licence

MIT, for the code. The word lists come from Braincup and carry their own
attribution in `NOTICE.md`.
