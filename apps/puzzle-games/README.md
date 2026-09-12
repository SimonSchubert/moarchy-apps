# puzzle-games

Packaging for [Puzzle](https://github.com/sidhant947/Puzzle) by sidhant947 — a
suite of 300+ minimalist logic, math and attention puzzles. Not an app written
here: this directory is a PKGBUILD, a `.desktop` file, and a one-branch patch.

## Smaller than apps/queens, and why

Queens gitignores `linux/` entirely, so the runner has to be *carried* there —
the file to change does not exist upstream, and a patch would have nothing to
apply to. Puzzle commits `linux/` alongside `snap/`, `macos/` and `windows/`:
upstream already supports the Linux desktop, `flutter build linux --release`
works against a clean checkout, and the whole delta is a diff against a real,
versioned file. So this carries `no-titlebar.patch` and nothing else.

## The one change

Flutter's Linux template hardcodes a GTK header bar on Wayland. On a phone that
is 40 logical pixels of a 720-pixel screen spent on a title and a close button,
in front of a compositor that owns the frame — here it costs a whole game card
in the list.

`PUZZLE_NO_TITLEBAR=1` asks for neither a header bar nor decorations and opens
at 360x720. Unset, the existing GNOME and X11 branches decide as before, so no
desktop behaviour changes. `puzzle-games.desktop` sets it.

It is upstream at [sidhant947/Puzzle#168](https://github.com/sidhant947/Puzzle/pull/168),
the sibling of [sidhant947/Queens#15](https://github.com/sidhant947/Queens/pull/15).
If it lands, `no-titlebar.patch` goes and only the PKGBUILD stays.

## Name

`puzzle-games`, not `puzzle`. `puzzles` — Simon Tatham's Portable Puzzle
Collection — is already in `extra`, and two packages one letter apart, both
collections of small logic games, is a trap laid for whoever types the shorter
one. It is also the name the app puts on its own title bar.

## Building

    packaging/release.sh puzzle-games 1.1.4
    # upload as the puzzle-games-v1.1.4 asset, then pin its sha256 in PKGBUILD

Needs Flutter and an aarch64 machine — the phone image builder or the VM, not
the Python container the other apps here use. The build takes about three
minutes; it is a much larger app than queens.
