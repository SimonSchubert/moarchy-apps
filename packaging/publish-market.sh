#!/bin/bash
# Put built packages into [market-apps], the prebuilt repo the Omarchy Mobile
# Market installs from -- after the phone's PIN, through its market-pacman
# helper. App Finder does not use it: it installs from the AUR.
#
#   scripts/package.sh habits                         # packages/moarchy-habits-*.pkg.tar.xz
#   packaging/publish-market.sh packages/moarchy-habits-0.2.0-1-any.pkg.tar.xz
#   packaging/publish-market.sh --dry-run packages/moarchy-*-0.2.*-any.pkg.tar.xz
#
# [market-apps] is served from this repo's gh-pages branch, aarch64/, beside
# nothing of ours but its packages: the rest of it -- the AUR apps the Market
# test run built -- is omarchy-market-test's aur/publish.sh's to write. So this
# never rebuilds the database. It works in a detached worktree of
# origin/gh-pages, adds each package with `repo-add --remove`, which drops the
# older version of that one package and its file, signs, and refuses to push
# if anything but our own packages and the database would change.
#
# Every package goes up with its source: <pkgbase>-<ver>-<rel>.src.tar.gz from
# packaging/srcpkg.sh (makepkg --allsource), beside it in aarch64/ and signed
# the same way. One that is missing is made first, from apps/<app>/PKGBUILD at
# the same version; a package whose source cannot be made is not published.
#
# The Market lists only its test run's apps (aur/apps.json), so ours here are
# installable by name and listed nowhere; they are kept in step because the
# database is shared, and omarchy-market-test's publish.sh keeps the versions
# mobile-market-data's aur/recommended.json names.
set -euo pipefail
cd "$(dirname "$0")/.."

FPR=${MARKET_SIGNING_FPR:-3CA83612E7F3108F442006B418305B893569BAD3}
REPO=market-apps
IMAGE=${IMAGE:-moarchy-qml}     # anything with pacman's repo-add
DRY=0
[[ ${1:-} == --dry-run ]] && { DRY=1; shift; }
[[ $# -gt 0 ]] || { echo "usage: publish-market.sh [--dry-run] <pkg.tar.xz>..." >&2; exit 1; }

gpg --list-secret-keys "$FPR" >/dev/null 2>&1 || { echo "no secret key $FPR in this keyring" >&2; exit 1; }
for p in "$@"; do
  [[ -f $p && $p == *.pkg.tar.* && $p != *.sig ]] || { echo "not a package: $p" >&2; exit 1; }
  [[ $(basename "$p") == moarchy-* ]] || { echo "not one of ours: $p" >&2; exit 1; }
done

# The source package that goes with each one, by the package's own .PKGINFO --
# pkgbase and the full version -- and made now if it is not there yet.
srcs=()
for p in "$@"; do
  info=$(tar -xOf "$p" .PKGINFO)
  base=$(sed -n 's/^pkgbase = //p' <<<"$info" | head -1)
  full=$(sed -n 's/^pkgver = //p' <<<"$info" | head -1)
  src=$(dirname "$p")/$base-$full.src.tar.gz
  if [[ ! -f $src ]]; then
    app=$(grep -lx "pkgname=$base" apps/*/PKGBUILD 2>/dev/null | head -1 | cut -d/ -f2)
    [[ -n $app ]] || { echo "no source for $(basename "$p"), and no app named $base" >&2; exit 1; }
    want=$(sed -n 's/^pkgver=//p' "apps/$app/PKGBUILD" | head -1)-$(sed -n 's/^pkgrel=//p' "apps/$app/PKGBUILD" | head -1)
    [[ $want == "$full" ]] ||
      { echo "no source for $(basename "$p"): apps/$app/PKGBUILD is $want now, not $full" >&2; exit 1; }
    OUT=$(dirname "$p") packaging/srcpkg.sh "$app"
  fi
  [[ -f $src ]] || { echo "no source package $src" >&2; exit 1; }
  srcs+=("$src")
done

git fetch -q origin gh-pages
wt=$(mktemp -d)/pages
git worktree add -q --detach "$wt" origin/gh-pages
trap 'git worktree remove --force "$wt" 2>/dev/null || true' EXIT

names=()
for p in "$@"; do
  gpg --batch --yes --detach-sign --no-armor --local-user "$FPR" "$p"
  cp "$p" "$p.sig" "$wt/aarch64/"
  names+=("$(basename "$p")")
done
for src in "${srcs[@]}"; do
  b=$(basename "$src"); base=${b%-*-*.src.tar.gz}
  # The older source of the same package goes, as repo-add --remove takes the
  # older package -- by exact shape, so moarchy-keep never takes moarchy-keep-x.
  for old in "$wt"/aarch64/"$base"-*.src.tar.gz; do
    [[ -f $old && ${old##*/} != "$b" && ${old##*/} =~ ^"$base"-[^-]+-[^-]+\.src\.tar\.gz$ ]] || continue
    rm -f "$old" "$old.sig"
  done
  gpg --batch --yes --detach-sign --no-armor --local-user "$FPR" "$src"
  cp "$src" "$src.sig" "$wt/aarch64/"
done

echo "==> $REPO.db"
docker run --rm --platform linux/arm64 -v "$wt/aarch64:/repo" "$IMAGE" \
  bash -c "cd /repo && repo-add -q --remove --include-sigs $REPO.db.tar.gz ${names[*]}"
rm -f "$wt"/aarch64/*.old "$wt"/aarch64/*.old.sig

# Real files, not repo-add's symlinks: Pages serves a symlink as its path. The
# old .sig has to go first -- cp calls a symlink and its target "identical"
# and leaves the symlink.
for base in db files; do
  gpg --batch --yes --detach-sign --no-armor --local-user "$FPR" "$wt/aarch64/$REPO.$base.tar.gz"
  rm -f "$wt/aarch64/$REPO.$base" "$wt/aarch64/$REPO.$base.sig"
  cp "$wt/aarch64/$REPO.$base.tar.gz" "$wt/aarch64/$REPO.$base"
  cp "$wt/aarch64/$REPO.$base.tar.gz.sig" "$wt/aarch64/$REPO.$base.sig"
done
gpg --verify "$wt/aarch64/$REPO.db.sig" "$wt/aarch64/$REPO.db" 2>&1 | grep -q "Good signature" ||
  { echo "the database signature does not verify" >&2; exit 1; }
[[ -z $(find "$wt/aarch64" -type l) ]] || { echo "a symlink is left in aarch64/" >&2; exit 1; }

git -C "$wt" add -A aarch64
# Nothing but our packages and the database may change.
stray=$(git -C "$wt" diff --cached --name-only | grep -vE "^aarch64/(moarchy-[^/]+\.(pkg\.tar\.[a-z]+|src\.tar\.gz)(\.sig)?|$REPO\.(db|files)(\.tar\.gz)?(\.sig)?)$" || true)
[[ -z $stray ]] || { echo "refusing: this would change files that are not ours:"; echo "$stray"; exit 1; } >&2
git -C "$wt" diff --cached --name-status | sed 's/^/    /'

if [[ $DRY -eq 1 ]]; then echo "==> dry run: not pushed"; exit 0; fi
git -C "$wt" commit -q -m "[$REPO]: ${names[*]}"
git -C "$wt" push -q origin HEAD:gh-pages
echo "==> pushed; Pages serves it in a minute or two"
