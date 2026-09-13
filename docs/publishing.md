# Publishing

Every app in this repository belongs in **three** places, and an app that has
reached only one of them is not finished:

| where | who it is for | what carries it |
|---|---|---|
| **the AUR** | anyone on Arch or Arch Linux ARM who is not running our image | `apps/<app>/PKGBUILD` + `.SRCINFO`, pushed to `ssh://aur@aur.archlinux.org/<pkgname>.git` |
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

As of 2026-09-13, and this table is the thing to re-check rather than trust:

| app | package | version | AUR | `[moarchy-apps]` | catalogue |
|---|---|---|---|---|---|
| keep | `moarchy-keep` | 0.1.1 | yes | yes | no — still `deferred` in `verdicts.toml` |
| habits | `moarchy-habits` | 0.1.2 | yes | yes | no |
| vitals | `moarchy-vitals` | 0.1.0 | yes | yes | **yes**, tested on `pinephone-a64` |
| chess | `moarchy-chess` | 0.1.0 | yes | yes | **yes** |
| reversi | `moarchy-reversi` | 0.1.0 | yes | yes | **yes** |
| tictactoe | `moarchy-tictactoe` | 0.1.0 | yes | yes | **yes** |
| solitaire | `moarchy-solitaire` | 0.1.0 | yes | yes | **yes** |
| pegsolitaire | `moarchy-pegsolitaire` | 0.1.0 | yes | yes | **yes** |
| minesweeper | `moarchy-minesweeper` | 0.1.0 | yes | yes | **yes** |
| mill | `moarchy-mill` | 0.1.0 | yes | yes | **yes** |
| fiveletters | `moarchy-fiveletters` | 0.1.0 | yes | yes | **yes** |
| breakout | `moarchy-breakout` | 0.1.0 | yes | yes | **yes** |
| queens | `queens` | 1.0.8 | no — upstream's name to claim | no — it is in `[moarchy]` | **yes** |
| puzzle-games | `puzzle-games` | 1.1.4 | no — upstream's name to claim | no — it is in `[moarchy]` | **yes** |

Twelve of fourteen are in all three. What is left is `keep` and `habits`, which
have no catalogue row, and the two Flutter ones, which are listed and in
`[moarchy]` but not on the AUR.

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

2. **~~The image does not carry `[moarchy-apps]`.~~** Fixed in the moarchy repo
   on 2026-09-13 (`docs/structure.md` R8c), and it was the blocker worth
   fixing first: moarchy-store's catalogue lists ten packages that live only in
   this repo, its helper installs by execing `pacman -S` against a name in a
   sync database, and without the stanza there is no sync database — so every
   one of those rows was a dead Install button on a freshly flashed phone while
   working on the developer's own handset, which had the stanza added by hand
   one afternoon and never written down.

   `image/configure.sh` no longer reads one hardcoded `[repo]`: it loops over
   every manifest section naming a `server`, so a third repo is a manifest
   edit. `image/verify.sh` checks the stanza and the cached `.db.sig` for each
   of them rather than for `moarchy.db` alone — and fails loudly if the list
   comes back empty, because a `for` over nothing prints nothing and passes,
   which is the shape of the original bug. Both repos are signed by the same
   key, so `moarchy-keyring` needed no change.

   Verified before shipping: a clean Arch ARM container carrying exactly the
   two stanzas the image now writes, trusting nothing but the key fetched from
   the published URL, syncs both databases and installs `moarchy-chess` with
   `Validated By : Signature`.

   **What it does not fix is a phone already in the field.** An image change
   reaches a device only through a reflash; `/etc/pacman.conf` is a `pacman`
   backup file and no package update rewrites it. Every handset flashed before
   this still needs the stanza added once, by hand or by something that has not
   been written yet.

3. **queens and puzzle-games are in the other repo.** Both are `arch=aarch64`
   Flutter builds and were published into `[moarchy]` with the distro's own
   pipeline, so they are installable and listed — and they are the reason the
   catalogue has Install buttons that work. Neither is on the AUR, and both
   could be: upstream's source plus the runner or patch this repo carries is
   exactly what an AUR package is.

4. **`[moarchy]` still ships `moarchy-keep-0.1.0`.** `[moarchy-apps]` carries
   0.1.1. Two repositories offering one package name at two versions, resolved
   by whichever stanza pacman reads first, is a thing to fix rather than to
   document a second time.

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
