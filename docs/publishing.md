# Publishing

Every app in this repository ships to the AUR, and that is how a phone gets it
too:

| where | who it is for | what carries it |
|---|---|---|
| **the AUR** | anyone on Arch or Arch Linux ARM -- and Omarchy Mobile, whose App Finder installs from it | `apps/<app>/PKGBUILD` + `.SRCINFO`, pushed by `.github/workflows/aur.yml` |
| **App Finder's recommendations** | the phone's user, who finds apps in App Finder rather than by name | an entry in [mobile-market-data](https://github.com/SimonSchubert/mobile-market-data)'s `aur/recommended.json`, with three screens and an icon |
| **`[market-apps]`** | the Omarchy Mobile Market's prebuilt repo -- a copy, not the way in | `scripts/package.sh` → `packaging/publish-market.sh` → this repo's `gh-pages` branch |

## How a phone gets an app

App Finder is the phone's way in. It lists the recommended apps first, with
their screens turning in a carousel, then the AUR apps the market test run
tried on a phone-sized screen, and installs any of them from the AUR: `yay`
builds the package on the phone, and its root steps go through `pkexec` --
the phone's PIN, answered by the shell's own PIN pad (`auth_admin_keep`, so
once per install). Nothing to configure, no repo or key to add. So an app of
ours reaches phones by being on the AUR at the version `recommended.json`
names, and is seen by being in that file.

There is one PKGBUILD per app. It pins a release tarball by sha256, the AUR
gets it verbatim, and whatever builds it -- an Arch desktop, a phone through
App Finder -- builds the same bytes from the same tag.

`[market-apps]` is the other store on the phone: the Omarchy Mobile Market
(omarchy-mobile-market) installs prebuilt AUR apps from it with its
`market-pacman` helper, also behind the PIN. It lists only the apps its test
run built (`aur/apps.json`), so our packages there are installable by name and
listed nowhere; they are kept in step anyway, with `publish-market.sh`, because
the database is shared -- `omarchy-market-test/aur/publish.sh` rebuilds it from
scratch and keeps the packages `recommended.json` names -- and a stale copy of
ours is worse than none.

## What is where today

As of 2026-09-28, and this table is the thing to re-check rather than trust:

| app | package | version | AUR | App Finder | `[market-apps]` |
|---|---|---|---|---|---|
| video-library | `moarchy-video-library` | 0.1.0 | yes | recommended, first | no |
| vitals | `moarchy-vitals` | 0.2.1 | yes | recommended | yes |
| tictactoe | `moarchy-tictactoe` | 0.2.0 | yes | recommended | yes |
| minesweeper | `moarchy-minesweeper` | 0.2.0 | yes | recommended | yes |
| reversi | `moarchy-reversi` | 0.2.0 | yes | recommended | yes |
| chess | `moarchy-chess` | 0.2.0 | yes | recommended | yes |
| mill | `moarchy-mill` | 0.2.0 | yes | recommended | yes |
| solitaire | `moarchy-solitaire` | 0.2.0 | yes | recommended | yes |
| pegsolitaire | `moarchy-pegsolitaire` | 0.2.0 | yes | recommended | yes |
| fiveletters | `moarchy-fiveletters` | 0.2.0 | yes | recommended | yes |
| breakout | `moarchy-breakout` | 0.2.0 | yes | recommended | yes |
| keep | `moarchy-keep` | 0.2.0 | yes | recommended | yes |
| habits | `moarchy-habits` | 0.2.0 | yes | recommended | yes |
| launches | `moarchy-launches` | 0.2.0 | yes | recommended | yes |
| food | `moarchy-food` | 0.2.0 | yes | recommended | yes |
| calculator | `moarchy-calculator` | 0.2.0 | yes | recommended | yes |
| weather | `moarchy-weather` | 0.2.0 | yes | recommended | yes |
| clock | `moarchy-clock` | 0.2.0 | yes | recommended | yes |
| calendar | `moarchy-calendar` | 0.2.0 | yes | recommended | yes |
| contacts | `moarchy-contacts` | 0.2.0 | yes | recommended | yes |
| files | `moarchy-files` | 0.2.0 | yes | recommended | yes |
| editor | `moarchy-editor` | 0.2.0 | yes | recommended | yes |
| mail | `moarchy-mail` | 0.2.0 | yes | recommended | yes |
| crypto-market | `crypto-market` | 1.2.0 | yes | recommended | no |
| couch-for-trakt | `couch-for-trakt` | 1.2.0 | yes | recommended | no |
| transit | `transit` | 1.2.0 | yes | recommended | no |
| airwaves | `airwaves` | 1.1.0 | yes | recommended | no |
| atlas | `moarchy-atlas` | 0.1.0 | yes | recommended | yes |
| trivia | `moarchy-trivia` | 0.1.0 | yes | recommended | yes |
| books | `moarchy-books` | 0.1.0 | yes | recommended | yes |
| authenticator | `moarchy-authenticator` | 0.1.0 | no -- not released yet | no | no |
| queens | `queens` | 1.0.8 | no -- upstream's name to claim | no | no |
| puzzle-games | `puzzle-games` | 1.1.4 | no -- upstream's name to claim | no | no |

`coins` was retired on 2026-09-27 for Crypto Market (`apps/crypto-market`),
which is published as `crypto-market` -- one of the packages of ours without
the `moarchy-` prefix, so `aur.yml` names them and `release.sh` takes the
tarball's name from the PKGBUILD. `moarchy-coins` 0.1.1 is still on the AUR.

## One shape: a package that is also a plugin

Every app here is the same shape (see [`shared/kit`](../shared/kit)): a package
that installs the QML tree to `/usr/share/moarchy-<app>` and a launcher,
`/usr/bin/moarchy-<app>`, that asks the running Omarchy shell for the plugin
first (`omarchy-shell shell summon <id>`) and otherwise starts the same tree as
its own Quickshell process. So one package runs on the phone, on an Omarchy
desktop and on any other Quickshell desktop.

`depends` is `quickshell` and the JetBrains Mono Nerd Font the kit's icons are
drawn in, plus whatever an app's helper needs (Python for Mail's IMAP helper,
GStreamer and zbar for Food's scanner). `quickshell` is `extra/quickshell` for
aarch64, so nothing comes from the AUR at install time. Each PKGBUILD's
`check()` runs the app's tests under `qmltestrunner` offscreen, which needs no
display, so it runs for every AUR user as it does here.

**What a package cannot do is put the app into the shell as a plugin.**
Upstream's shell loads third-party plugins only from
`~/.config/omarchy/plugins`, enabled by an id in the per-user `shell.json`,
which a package must not write. So the packaged app opens as its own process,
and `scripts/install-plugin.sh` copies an app into the home directory and
enables it, for a phone or a VM that wants it inside the shell.

## Releasing, end to end

```sh
# 1. green, in the container, and look at the photographs
docker run --rm -v "$PWD:/src" -w /src moarchy-qml scripts/check.sh <app>
docker run --rm -v "$PWD:/src" -w /src moarchy-qml scripts/app-shot.sh <app>

# 2. tag, push the tag, build the tarball from it
git tag -a <app>-v<version> -m "<app> <version>" && git push origin <app>-v<version>
packaging/release.sh <app> <version>        # -> dist/moarchy-<app>-<version>.tar.gz + sha256

# 3. upload the SAME file as the release asset, then pin its checksum.
#    The tarball is a function of the tag's commit date, so never move the tag.
gh release create <app>-v<version> dist/moarchy-<app>-<version>.tar.gz
$EDITOR apps/<app>/PKGBUILD                 # sha256sums

# 4. .SRCINFO from the PKGBUILD (makepkg, so: the container, as a user)
(cd apps/<app> && makepkg --printsrcinfo > .SRCINFO)

# 5. commit and push: aur.yml publishes every app whose PKGBUILD or .SRCINFO
#    changed -- namcap, .SRCINFO against a fresh one, the asset's checksum,
#    then the push. A new package base is created by its first push.
git commit -am "Pin <app> <version> to its release asset, with its .SRCINFO" && git push

# 6. the Market's copy
scripts/package.sh <app>                    # -> packages/moarchy-<app>-<version>-1-any.pkg.tar.xz
packaging/publish-market.sh packages/moarchy-<app>-<version>-1-any.pkg.tar.xz
```

Then, for an app App Finder should show: a new or updated entry in
mobile-market-data's `aur/recommended.json` -- the same fields as an
`aur/apps.json` entry, the version now on the AUR, and a 144 px icon. Its
screens are the app's own: the three lines named `store-*` in its
`dev/shots`, which

```sh
MARKET_DATA=../mobile-market-data packaging/publish-store.sh <app>
```

shoots in every theme Omarchy ships (`app-shot.sh`'s `THEMES=` mode), as WebP
named by content hash, into the entry's `themed` map -- App Finder shows a
phone the three in its own theme -- and its `shots`, the Tokyo Night three, for
any other. Then commit and push the data repo; phones fetch it at most hourly.
The shots are the same bytes on every run, so an app that did not change adds
nothing.

A few things that fail late rather than loudly:

- **The AUR's branch is `master`.** `aur.yml` pushes `HEAD:refs/heads/master`;
  by hand, a fresh clone of a base that does not exist yet has no branch, and a
  plain `git push` creates nothing.
- **A stale `.SRCINFO`** advertises the wrong dependencies to every AUR helper
  while the PKGBUILD quietly builds something else. `aur.yml` fails on it, which
  is also why a push of PKGBUILDs at `sha256sums=('SKIP')` publishes nothing.
- **The version in `recommended.json`** is the one App Finder shows, and the
  one `omarchy-market-test/aur/publish.sh` keeps in `[market-apps]`: bump it
  with the release.
- **`[market-apps]`'s database is shared.** Never rebuild it from `packages/`
  with `repo-add --new`: that deletes the AUR apps. `publish-market.sh` refuses
  to push a diff that touches them.

## The checklist, short

For each app, in this order:

- [ ] `scripts/check.sh <app>` green, the photographs looked at
- [ ] tag pushed, `packaging/release.sh`, asset uploaded, checksum pinned
- [ ] `.SRCINFO` regenerated, committed, pushed -- `aur.yml` green
- [ ] `recommended.json` entry, screens and icon, at the new version
- [ ] `scripts/package.sh`, `packaging/publish-market.sh`
