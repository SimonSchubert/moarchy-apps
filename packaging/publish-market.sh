#!/bin/bash
# Put built packages into [market-apps], the repo the Omarchy Mobile Market
# installs from -- after the phone's PIN, through its market-pacman helper.
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
# An app the Market should show, and not only offer, also needs an entry in
# mobile-market-data's aur/recommended.json: App Finder lists the test run's
# apps and the recommended ones, and a package the repo merely carries is
# installable by name and found by nobody.
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
stray=$(git -C "$wt" diff --cached --name-only | grep -vE "^aarch64/(moarchy-[^/]+\.pkg\.tar\.[a-z]+(\.sig)?|$REPO\.(db|files)(\.tar\.gz)?(\.sig)?)$" || true)
[[ -z $stray ]] || { echo "refusing: this would change files that are not ours:"; echo "$stray"; exit 1; } >&2
git -C "$wt" diff --cached --name-status | sed 's/^/    /'

if [[ $DRY -eq 1 ]]; then echo "==> dry run: not pushed"; exit 0; fi
git -C "$wt" commit -q -m "[$REPO]: ${names[*]}"
git -C "$wt" push -q origin HEAD:gh-pages
echo "==> pushed; Pages serves it in a minute or two"
