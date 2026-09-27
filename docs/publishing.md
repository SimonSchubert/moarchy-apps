# Publishing

Every app in this repository belongs in **three** places, and an app that has
reached only one of them is not finished:

| where | who it is for | what carries it |
|---|---|---|
| **the AUR** | anyone on Arch or Arch Linux ARM who is not running the phone image | `apps/<app>/PKGBUILD` + `.SRCINFO`, pushed to `ssh://aur@aur.archlinux.org/<pkgname>.git` |
| **`[moarchy-apps]`** | the phone: a signed pacman repo, so the store's privileged helper can install it | `packaging/repo-add.sh` → `packaging/publish-pages.sh` → the `gh-pages` branch |
| **moarchy-store's catalogue** | the phone's user, who does not know a package name to type | a row in `catalogue.toml`, an entry in `metadata.toml`, screenshots, and a verdict in `sweep/verdicts.toml` |

## Why all three, when the argument used to be either/or

The commit that published the seven games to the signed repo said *"deliberately
not the AUR"*, and what it argued was right as far as it went: moarchy-store's
helper execs `pacman -S` against a signed allowlist, an AUR package is in no sync
database, so the store cannot install one **at all**. Nine AUR pushes would have
been nine promises in a channel the phone cannot read, and `sweep/verdicts.toml`
still holds `moarchy-keep` as *"AUR only, and ours"* — deferred from a store we
wrote — as the evidence for how that ends.

That is an argument for the signed repo being the channel the **store** installs
from. It was never an argument against the AUR, because the AUR is not aimed at
the phone: it is aimed at everybody else. These are GTK4/libadwaita apps drawn
for 360px, which is a shape a laptop user has no other source for, and the AUR is
where an Arch user looks first. Publishing there costs one `git push` per release
of files this repository already has to contain.

So the rule is **both, for every app**, and the two cannot drift — which is what
makes carrying both cheap. There is one PKGBUILD per app, in `apps/<app>/`, and
it pins a release tarball by sha256. The AUR gets that file verbatim;
`scripts/package.sh` builds the binary package from the same tree; both install
the same bytes from the same tag. The only thing the AUR needs that the repo does
not is `.SRCINFO`, and that is generated from the PKGBUILD rather than written.

## What is where today

As of 2026-09-14, and this table is the thing to re-check rather than trust:

| app | package | version | AUR | `[moarchy-apps]` | catalogue |
|---|---|---|---|---|---|
| keep | `moarchy-keep` | 0.1.1 released; 0.2.0, the Quickshell rewrite, in the tree and not tagged | yes | yes | no — still `deferred` in `verdicts.toml` |
| habits | `moarchy-habits` | 0.1.2 released; 0.2.0, the Quickshell rewrite, in the tree and not tagged | yes | yes | no |
| vitals | `moarchy-vitals` | 0.2.0, the Quickshell rewrite; 0.2.1, on the kit, not tagged | yes | 0.1.0 still — the GTK app | **yes**, tested on `pinephone-a64` — 0.1.0, the GTK app |
| chess | `moarchy-chess` | 0.1.0 released; 0.2.0, the Quickshell rewrite, in the tree and not tagged | yes | yes | **yes** — 0.1.0, the GTK app |
| reversi | `moarchy-reversi` | 0.1.0 released; 0.2.0, the Quickshell rewrite, in the tree and not tagged | yes | yes | **yes** — 0.1.0, the GTK app |
| tictactoe | `moarchy-tictactoe` | 0.1.0 released; 0.2.0, the Quickshell rewrite, in the tree and not tagged | yes | yes | **yes** — 0.1.0, the GTK app |
| solitaire | `moarchy-solitaire` | 0.1.0 released; 0.2.0, the Quickshell rewrite, in the tree and not tagged | yes | yes | **yes** — 0.1.0, the GTK app |
| pegsolitaire | `moarchy-pegsolitaire` | 0.1.0 released; 0.2.0, the Quickshell rewrite, in the tree and not tagged | yes | yes | **yes** — 0.1.0, the GTK app |
| minesweeper | `moarchy-minesweeper` | 0.1.0 released; 0.2.0, the Quickshell rewrite, in the tree and not tagged | yes | yes | **yes** — 0.1.0, the GTK app |
| weather | `moarchy-weather` | 0.2.0, the first package — until then a shell plugin copied by hand; in the tree and not tagged | no | no | no |
| clock | `moarchy-clock` | 0.2.0, the first package (a shell plugin until now), in the tree and not tagged | no | no | no |
| editor | `moarchy-editor` | 0.2.0, the first package (a shell plugin until now), in the tree and not tagged | no | no | no |
| mill | `moarchy-mill` | 0.1.0 released; 0.2.0, the Quickshell rewrite, in the tree and not tagged | yes | yes | **yes** — 0.1.0, the GTK app |
| fiveletters | `moarchy-fiveletters` | 0.1.0 released; 0.2.0, the Quickshell rewrite, in the tree and not tagged | yes | yes | **yes** — 0.1.0, the GTK app |
| breakout | `moarchy-breakout` | 0.1.0 released; 0.2.0, the Quickshell rewrite, in the tree and not tagged | yes | yes | **yes** — 0.1.0, the GTK app |
| launches | `moarchy-launches` | 0.2.0, the Quickshell rewrite, in the tree and not tagged; 0.1.0 was never released | no | no | no |
| food | `moarchy-food` | 0.2.0, the Quickshell rewrite, in the tree and not tagged; 0.1.0 was never released | no | no | no |
| files | `moarchy-files` | 0.2.0, its first package — 0.1.0 was a shell plugin only — in the tree and not tagged | no | no | no |
| calculator | `moarchy-calculator` | 0.2.0, its first package — 0.1.0 was a shell plugin only — in the tree and not tagged | no | no | no |
| contacts | `moarchy-contacts` | 0.2.0, its first package — 0.1.0 was a shell plugin only — in the tree and not tagged | no | no | no |
| calendar | `moarchy-calendar` | 0.2.0, its first package — 0.1.0 was a shell plugin only — in the tree and not tagged | no | no | no |
| mail | `moarchy-mail` | 0.2.0, its first package — 0.1.0 was a shell plugin only — in the tree and not tagged | no | no | no |
| queens | `queens` | 1.0.8 | no — upstream's name to claim | no — it was in moarchy's `[moarchy]` | **yes** |
| puzzle-games | `puzzle-games` | 1.1.4 | no — upstream's name to claim | no — it was in moarchy's `[moarchy]` | **yes** |
| coins | `moarchy-coins` | 0.1.1 | to be deleted | to be dropped | to be dropped — replaced by `crypto-market`, see below |
| crypto-market | `crypto-market` | 1.1.1 | yes | no — AUR only | no |
| couch-for-trakt | `couch-for-trakt` | 1.1.0 | yes | no — AUR only | no |
| transit | `transit` | 1.1.0 | yes | no — AUR only | no |
| airwaves | `airwaves` | 1.0.0 | yes | no — AUR only | no |

Thirteen of fifteen are in all three. What is left is `keep` and `habits`,
which have no catalogue row, and the two Flutter ones, which are listed but
were only ever built into moarchy's own `[moarchy]` and are not on the AUR.

`coins` was retired on 2026-09-27 for Crypto Market, `apps/crypto-market`: a
Quickshell app published as `crypto-market`, on the AUR only. It is the one
package of ours without the `moarchy-` prefix, so `aur.yml` names it and
`release.sh` takes the tarball's name from the PKGBUILD. Nothing carries an
installed `moarchy-coins` over: it is dropped from the AUR, `[moarchy-apps]`
and the catalogue.

`couch-for-trakt` followed the same day, from the `omarchy-couch` plugin
repository, on the same terms: AUR only, named in `aur.yml`. So did `transit`, from
`omarchy-transit`, and `airwaves`, written here in Couch's shape.

What follows is the history of the version of Coins that left.

`coins` went through all three on 2026-09-14, in the order this file gives, and
it is the row that proves the order matters: the catalogue lint fails an entry
whose package is in no sync database the phone can read, so the signed repo had
to be published — and its cached copy of that database refreshed — before the
row could pass. What it did **not** go through is a device. The
omarchy-mobile checkout is not on the machine that did this, so `tested` and
`measured` are both empty, the store renders the entry as *"Not yet tested on a
device"*, and `lint-catalogue.py` prints a warning naming it. That warning is
correct and should stay until somebody runs `scripts/sweep-measure.sh` against
it. Every other row of ours says `pinephone-a64` because somebody held the
phone; this one says nothing, and the difference is the whole point of the
field.

It also released twice in an afternoon. 0.1.0 drew the rank column from
CoinGecko's `market_cap_rank`, which on the day came back with two coins at 9
and drew a list numbered 8, 9, 9, 10 — found by pointing the app at the live
endpoint to take the catalogue screenshot, which is the one thing a fixture
cannot do. 0.1.1 numbers by position in the answer. The AUR and the signed repo
both carry 0.1.1; 0.1.0 remains a GitHub release, because a tag that has been
pushed is not a thing to move.

The nine games were listed at catalogue serial 26 and measured on a PinePhone
A64 rather than in the VM — the device already had seven of them installed, so
the cost was two `pacman -S` from `[moarchy-apps]` and nine photographs. That
makes `tested = "pinephone-a64"` on each of them a claim about hardware, which
is the strongest thing that field can say.

Each of the nine added on 2026-09-13 was checked before it was pushed, the same
way the workflow checks: `namcap` clean, `.SRCINFO` identical to one generated
from the PKGBUILD, the release asset fetched and its sha256 compared against the
pin, and then a real `makepkg` in a clean Arch ARM container — which downloads
the tarball, validates the checksum, and runs the package's own `check()`. That
last one is not ceremony: `makepkg` runs `check()` for every AUR user, so a test
needing a display would break the install for all of them. They skip the widget
tests and run the rest, 60 to 179 of them per app.

## The QML plugins are a fourth shape, and only one half of them can be published

`plugins/` holds apps that are not processes. A shell plugin is QML the running
`omarchy-shell` loads and keeps loaded, so summoning Keep or Launches is
`visible = true` on a window that already exists rather than four seconds of
starting Python and GTK. That is the whole reason they exist, and it is also
why none of the three channels above fits them without an argument.

What a plugin needs is not what a package can promise. Quickshell, a Wayland
compositor with layer shell, the plugin host's `manifest.json` contract and the
`shell` object it injects, and an id listed in `~/.config/omarchy/shell.json`
before anything loads it. The last one is user configuration: a package can
ship files, it cannot enable itself.

**The scan roots are the check to do first, and on Omarchy Mobile they answer
no.** Upstream's shell has two: `$OMARCHY_PATH/shell/plugins` for first-party
plugins, which is where Mobile installs its own UI, and
`~/.config/omarchy/plugins` for everything else (`shell/services/PluginRegistry.qml`).
There is no system-wide root for a third-party plugin, so a package has nowhere
to put one that the shell will find and the package will own. Mobile's own
plugins avoid the question by being first-party; a plugin from this repo is not,
and `install-on-device.sh` copies it into the home directory instead, which is
a copy `pacman` knows nothing about.

The enable step is a second problem behind the first: the id in
`~/.config/omarchy/shell.json`. Writing that file from a package is not the
answer — it is per-user, and a user copy masks the packaged defaults. Until
both are solved the standalone entry point below covers it, so this is a
question of how fast the app opens, not whether it runs.

The standalone half is publishable, and as of 2026-09-15 it exists.
`shared/qs_ui` no longer imports anything from the shell, so an app built on it
runs under a plain Quickshell: `plugins/<id>/shell.qml` is the same app as its
own process, and `run-local.sh` vendors the kit and starts it. Three couplings
had to go, and each was replaced with something that still resolves to the
shell's own answer on the phone rather than an approximation of it:

- `Style.font.body` → `Metrics.shellBody()`, which compiles `import qs.Commons`
  as a string once at startup. An unresolved QML import fails the whole file at
  load time, so a string is the only way to make one optional. Inside the shell
  it returns the shell's body size, and text scaling still reaches the app.
- `qs.Ui.TextField` → a plain `TextInput`. Text reaches it without the shell:
  `moarchy-keyboard` binds `zwp_input_method_v2` and Qt speaks text-input-v3
  for whatever holds focus. Focus does not raise the keyboard, though, so the
  kit's `Osk` asks `sm.puri.OSK0` on a press, and on another desktop that call
  finds nobody and does nothing.
- `Util.alpha` → `Theme.alpha`, the same `Qt.rgba` call.

So a QML app can be an AUR package: the QML tree plus `shared/qs_ui` vendored
into it at build time, `depends=('quickshell' 'qt6-5compat' 'adwaita-icon-theme')`,
a `.desktop` whose `Exec` is `quickshell -p`. `qt6-5compat` is named because
`Icon.qml` tints through `Qt5Compat.GraphicalEffects`, and `qt6-declarative` is
not, because `quickshell` already depends on it — `namcap` runs on every publish
and a redundant dependency is what it is for.

**`quickshell` is not AUR-only, and that changes what the package is worth.**
It is `extra/quickshell 0.3.1-1`, `Architecture: aarch64`, and `pacman -Sp
quickshell` resolves the whole closure — qt6-base, qt6-declarative, qt6-svg,
qt6-wayland and the rest — out of the repositories with no AUR helper anywhere
in it. Measured in a clean Arch Linux ARM container rather than assumed, which
is the only reason the sentence that used to sit here was wrong: it was true
when quickshell was young, and it stopped being true without anything in this
repo noticing.

What is left of the honest caveat is smaller and still worth saying: an Arch
user who wants a launch tracker is installing a shell toolkit to get one, and
that is a real cost even when `pacman` pays it in one transaction. The
portability is worth having regardless, because it is what stops the kit from
quietly becoming a thing only our shell can run.

## The gaps that are structural, not just unfinished rows

1. **~~CI publishes one app.~~** Fixed: `.github/workflows/aur.yml` is matrixed
   over every app whose `.SRCINFO` declares a `pkgbase` beginning with
   `moarchy-`, so a commit that touches an app's PKGBUILD or `.SRCINFO`
   publishes that app and nothing else, and `workflow_dispatch` takes one app
   name or none for all of them. The prefix is the rule because `queens` and
   `puzzle-games` carry upstream's names: a new app of ours is published the day
   it is added, and a new one of theirs is never published by accident.

   Worth knowing, because it was true for as long as the workflow existed: the
   checksum step could only ever fail. It read the source URL with
   `grep -oP '^\s+source = .*::\K\S+'`, which requires a `name::url` source,
   and every `.SRCINFO` here carries a plain URL — so the pattern matched
   nothing, `curl` was handed an empty string, and the step died. Nobody saw it
   because the only app it was wired to was updated by hand. It reads the field
   with `awk` now, and still strips a `name::` prefix if one is ever used.

2. **No image carries `[moarchy-apps]`.** The moarchy image did, and moarchy is
   no longer developed; Omarchy Mobile, which replaced it, has its own
   `[omarchy-mobile]` repo and no stanza for this one. Until it does, a phone
   gets the stanza from the README by hand, and a catalogue row for a package
   that lives only here is an Install button that works on that phone and on no
   other.

3. **queens and puzzle-games were only ever in moarchy's repo.** Both are
   `arch=aarch64` Flutter builds and were published into `[moarchy]` with that
   distro's pipeline. Neither is on the AUR, and both could be: upstream's
   source plus the runner or patch this repo carries is exactly what an AUR
   package is — and it is now the only way either reaches a phone.

## Releasing one app, end to end

Nothing below is new machinery; it is the order the existing scripts have to run
in, which is the part that was never written down.

```sh
# 1. green first, in the container -- ruff, tests, a real run at 360x720,
#    the icon lint and the PKGBUILD lint that catches an install path
#    naming a file nobody has.
scripts/check.sh <app>

# 2. tag, then build the tarball from the tag
git tag <app>-v<version> && git push origin <app>-v<version>
packaging/release.sh <app> <version>        # -> dist/moarchy-<app>-<version>.tar.gz + sha256

# 3. pin it, and upload the SAME file as the release asset.
#    The tarball is a function of the tag's commit date, so pin the checksum
#    after the tag is final and never move the tag afterwards.
$EDITOR apps/<app>/PKGBUILD                 # pkgver + sha256sums
gh release create <app>-v<version> dist/moarchy-<app>-<version>.tar.gz

# 4. regenerate .SRCINFO from the PKGBUILD (needs makepkg, so: container)
cd apps/<app> && makepkg --printsrcinfo > .SRCINFO
```

Then the three channels. **AUR:**

```sh
git clone ssh://aur@aur.archlinux.org/<pkgname>.git   # pushing creates it
cp apps/<app>/{PKGBUILD,.SRCINFO} <pkgname>/ && cd <pkgname>
git commit -am "Update <pkgname>"
git push origin HEAD:refs/heads/master               # master, and HEAD: matters
```

**The branch is `master`.** Cloning a package base that does not exist yet gives
an empty repository, where git names the first branch after this machine's
`init.defaultBranch` — `main`, here — so a plain `git push` or `git push origin
master` fails with *"src refspec master does not match any"* and creates
nothing. `HEAD:refs/heads/master` is what an initial import needs. `aur.yml`
never hits this because it only ever pushes to package bases that already exist.

The first commit on a new base follows the convention the existing ones set:
`Initial import: <pkgname> <version>`, then `Update <pkgname>` after that.

`<pkgname>` is `moarchy-<app>` for everything written here and upstream's own
name for the two that are packaging only — `queens`, `puzzle-games` — which is
also what they would be called on the AUR.

`aur.yml` already does the three checks worth keeping when this is finally
matrixed over every app: `namcap` on the PKGBUILD, a diff of `.SRCINFO` against
a freshly generated one, and a fetch of the release asset to confirm the pinned
sha256 is the checksum of the file that is actually there. A stale `.SRCINFO`
advertises the wrong dependencies to every helper while the PKGBUILD quietly
builds something else, and a wrong checksum fails at `makepkg` on somebody
else's machine rather than on ours.

**`[moarchy-apps]`,** which is two halves because the two tools it needs are on
different machines — `repo-add` is pacman's and lives in the Arch container, the
secret key is on the laptop and has no reason to travel:

```sh
scripts/package.sh <app>                       # container -> packages/*.pkg.tar.xz
gpg --detach-sign --no-armor packages/moarchy-<app>-*.pkg.tar.xz   # laptop
packaging/repo-add.sh packages/*.pkg.tar.*     # container: builds the .db
packaging/publish-pages.sh                     # laptop: signs the .db, resolves
git push origin gh-pages                       #         the symlinks, publishes
```

`repo-add.sh` will sign anything unsigned if `MOARCHY_SIGNING_KEY` names a key
that is actually in the keyring, and refuses to build an unsigned repo otherwise
— `ALLOW_UNSIGNED=1` exists and gives away the one advantage this has over the
AUR, so it is for debugging and not for a release.

**The catalogue**, in moarchy-store, and this is the half that is not a push.
`.claude/skills/catalogue-sweep` there runs the whole loop; the scripts under it
are:

```sh
scripts/sweep-measure.sh <pkg>      # install it in the VM at 360x674: cost,
                                    # geometry, the light/dark diff, screenshots
scripts/sweep-record.py --from /tmp/measured --adaptive fits <pkg>
                                    # merge that into metadata.toml
cp /tmp/measured/<pkg>-dark.png screenshots/ && scripts/sweep-shots.sh
                                    # pngquant + oxipng, in place
$EDITOR sweep/verdicts.toml catalogue.toml metadata.toml   # verdict, row, prose
$EDITOR catalogue.toml              # bump `serial`
python3 scripts/lint-catalogue.py
scripts/sign-catalogue.sh && git commit -a && git push
```

Four things there are not optional, and each of them is a check that fails late
rather than a convention:

- **`sweep-record.py` will not write `adaptive` unless you pass it.** The harness
  reports *mapped*, never *fits* — Hyprland tiles, so it forces 360x674 onto an
  app that cannot cope, and a clipped app reports the same geometry as a perfect
  one. Whether it fits is a judgement made by looking at the picture.
- **The verdict and the row have to agree.** `lint-catalogue.py` fails on a
  `verdicts.toml` entry marked `listed` that is not in `catalogue.toml`, so when
  `moarchy-keep`'s row finally lands, its `deferred` / *"AUR only, and ours"*
  verdict is part of the same commit.
- **`serial` must increase.** Clients refuse a fetched catalogue whose serial is
  not above the one they already trust, which is what stops a replayed older
  catalogue from re-adding something that was removed.
- **The package must be in a sync database `syncdb.py` knows about** — `core`,
  `extra`, `[moarchy]` or `[moarchy-apps]` — or the lint calls the Install button
  dead. It has been wrong about that in the direction that matters once already,
  which is gap 2 above: the lint models a repo the *image* does not yet carry.

Screenshots are fetched from GitHub at runtime rather than packaged, so their
size is somebody's mobile data — hence the squeeze step. An entry with an empty
`tested` renders as *"Not yet tested on a device"*: a suggestion. A device string
is a claim someone can hold us to, and `sweep-record.py` will never overwrite one
with a VM run.

Once signed and pushed, every installed store picks the catalogue up on next
launch. No package update, no AUR push — that is the whole point of signing it.

## The checklist, short

For each app, in this order:

- [ ] `scripts/check.sh <app>` green in the container
- [ ] tag, `packaging/release.sh`, checksum pinned, asset uploaded
- [ ] `.SRCINFO` regenerated and committed
- [ ] pushed to the AUR
- [ ] package built, signed, in `[moarchy-apps]`, `gh-pages` pushed
- [ ] measured and shot in the VM, verdict recorded
- [ ] row in `catalogue.toml`, entry in `metadata.toml`, `serial` bumped,
      catalogue re-signed and pushed
