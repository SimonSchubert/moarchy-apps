# Publishing

Every app in this repository ships in **two** places, and a third decides
whether a phone's user ever sees it:

| where | who it is for | what carries it |
|---|---|---|
| **the AUR** | anyone on Arch or Arch Linux ARM, on a desktop or a phone | `apps/<app>/PKGBUILD` + `.SRCINFO`, pushed by `.github/workflows/aur.yml` |
| **`[market-apps]`** | Omarchy Mobile: the signed repo its Market installs from, after the phone's PIN | `scripts/package.sh` → `packaging/publish-market.sh` → this repo's `gh-pages` branch |
| **App Finder's recommendations** | the phone's user, who finds apps in App Finder rather than by name | an entry in [mobile-market-data](https://github.com/SimonSchubert/mobile-market-data)'s `aur/recommended.json`, with three screens and an icon |

## Why two channels

The AUR is where an Arch user looks, and it is somebody else's server: it
carries source, a PKGBUILD pinning a release tarball, and every user builds.
A phone should not compile anything, and the Market's installer will only run
`pacman -S` against its own signed repo -- `libexec/market-pacman` in
omarchy-mobile-market refuses any package `[market-apps]` does not offer. So a
phone gets the binary package from `[market-apps]`, installed through App
Finder with the phone's PIN (polkit's `auth_admin_keep`, answered by the
shell's own PIN pad), and nothing to configure: the Market's package adds the
repo to `pacman.conf` and trusts its key.

The two cannot drift. There is one PKGBUILD per app, it pins a release tarball
by sha256, the AUR gets that file verbatim, and `scripts/package.sh` builds the
binary package from the same tree -- the same bytes, from the same tag.

`[market-apps]` is shared: omarchy-mobile-market's test run publishes the AUR
apps it built and tested into the same database, from
`omarchy-market-test/aur/publish.sh`. That script rebuilds the database from
scratch and keeps the packages `recommended.json` names, from this repo's
`packages/`; `packaging/publish-market.sh` adds ours to the database as it is
and refuses to push a change to anything that is not ours.

A package in `[market-apps]` that App Finder does not list is installable by
name and found by nobody. App Finder lists the test run's apps and the
recommended ones, first, with their screens turning in a carousel; an app of
ours becomes visible by getting an entry there.

## What is where today

As of 2026-09-28, and this table is the thing to re-check rather than trust:

| app | package | version | AUR | `[market-apps]` | App Finder |
|---|---|---|---|---|---|
| vitals | `moarchy-vitals` | 0.2.1 | yes | yes | recommended |
| tictactoe | `moarchy-tictactoe` | 0.2.0 | yes | yes | recommended |
| minesweeper | `moarchy-minesweeper` | 0.2.0 | yes | yes | recommended |
| reversi | `moarchy-reversi` | 0.2.0 | yes | yes | recommended |
| chess | `moarchy-chess` | 0.2.0 | yes | yes | recommended |
| mill | `moarchy-mill` | 0.2.0 | yes | yes | recommended |
| solitaire | `moarchy-solitaire` | 0.2.0 | yes | yes | recommended |
| pegsolitaire | `moarchy-pegsolitaire` | 0.2.0 | yes | yes | recommended |
| fiveletters | `moarchy-fiveletters` | 0.2.0 | yes | yes | recommended |
| breakout | `moarchy-breakout` | 0.2.0 | yes | yes | recommended |
| keep | `moarchy-keep` | 0.2.0 | yes | yes | not listed |
| habits | `moarchy-habits` | 0.2.0 | yes | yes | not listed |
| launches | `moarchy-launches` | 0.2.0 | yes | yes | not listed |
| food | `moarchy-food` | 0.2.0 | yes | yes | not listed |
| calculator | `moarchy-calculator` | 0.2.0 | yes | yes | not listed |
| weather | `moarchy-weather` | 0.2.0 | yes | yes | not listed |
| clock | `moarchy-clock` | 0.2.0 | yes | yes | not listed |
| calendar | `moarchy-calendar` | 0.2.0 | yes | yes | not listed |
| contacts | `moarchy-contacts` | 0.2.0 | yes | yes | not listed |
| files | `moarchy-files` | 0.2.0 | yes | yes | not listed |
| editor | `moarchy-editor` | 0.2.0 | yes | yes | not listed |
| mail | `moarchy-mail` | 0.2.0 | yes | yes | not listed |
| crypto-market | `crypto-market` | 1.1.1 | yes | no | recommended, not installable yet |
| couch-for-trakt | `couch-for-trakt` | 1.1.0 | yes | no | recommended, not installable yet |
| transit | `transit` | 1.1.0 | yes | no | recommended, not installable yet |
| airwaves | `airwaves` | 1.0.0 | yes | no | recommended, not installable yet |
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

# 6. the phone
scripts/package.sh <app>                    # -> packages/moarchy-<app>-<version>-1-any.pkg.tar.xz
packaging/publish-market.sh packages/moarchy-<app>-<version>-1-any.pkg.tar.xz
```

Then, for an app App Finder should show: a new or updated entry in
mobile-market-data's `aur/recommended.json` -- the same fields as an
`aur/apps.json` entry, the version `[market-apps]` now carries, three screens
at 540 px (`app-shot.sh` with `SIZE=540x1044 SCALE=1.5`, as WebP named by
content hash) and a 144 px icon. Phones fetch it at most hourly.

A few things that fail late rather than loudly:

- **The AUR's branch is `master`.** `aur.yml` pushes `HEAD:refs/heads/master`;
  by hand, a fresh clone of a base that does not exist yet has no branch, and a
  plain `git push` creates nothing.
- **A stale `.SRCINFO`** advertises the wrong dependencies to every AUR helper
  while the PKGBUILD quietly builds something else. `aur.yml` fails on it, which
  is also why a push of PKGBUILDs at `sha256sums=('SKIP')` publishes nothing.
- **The version in `recommended.json`** has to be the one `[market-apps]`
  carries: `omarchy-market-test/aur/publish.sh` keeps exactly that package, and
  App Finder offers exactly that.
- **`[market-apps]`'s database is shared.** Never rebuild it from `packages/`
  with `repo-add --new`: that deletes the AUR apps. `publish-market.sh` refuses
  to push a diff that touches them.

## The checklist, short

For each app, in this order:

- [ ] `scripts/check.sh <app>` green, the photographs looked at
- [ ] tag pushed, `packaging/release.sh`, asset uploaded, checksum pinned
- [ ] `.SRCINFO` regenerated, committed, pushed -- `aur.yml` green
- [ ] `scripts/package.sh`, `packaging/publish-market.sh`
- [ ] `recommended.json` entry, screens and icon, if App Finder should show it
