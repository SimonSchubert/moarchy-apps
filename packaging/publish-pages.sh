#!/bin/bash
# Publish a built [moarchy-apps] repo to GitHub Pages.
#
#   packaging/repo-add.sh packages/*.pkg.tar.*     # in the Arch container
#   packaging/publish-pages.sh                     # here, where the key is
#
# The split is not tidiness. `repo-add` is pacman's and lives in an Arch
# container; the secret key is on this machine and has no reason to be anywhere
# else. So the database is assembled there and signed here, and this script is
# the second half.
#
# What it does that a `git push` of the directory would not:
#
# 1. **It signs the database.** `SigLevel = Required TrustedOnly` in the image's
#    pacman.conf applies to databases as well as to packages -- the words
#    Package and Database prefix a level, and unprefixed means both. A repo
#    whose packages are all signed and whose database is not is a repo the
#    phone refuses to sync, with an error about the database and nothing about
#    the packages anybody spent the afternoon signing.
#
# 2. **It resolves the symlinks.** repo-add leaves `moarchy-apps.db` as a
#    symlink to `moarchy-apps.db.tar.gz`, which is the convention on a real
#    mirror and a broken file on GitHub Pages: git stores the link, Pages serves
#    its target *path* as the body, and pacman downloads seventeen bytes of text
#    where it wanted a database. `moarchy-apps.db` is what pacman actually asks
#    for, so it has to be the bytes.
#
# 3. **It publishes the public key**, because a device cannot trust a signature
#    from a key it has never seen. `pacman-key --add moarchy-apps.gpg` and
#    `pacman-key --lsign-key <fpr>` is the other half of the pinned stanza in
#    /etc/pacman.conf.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${REPO:-moarchy-apps}"
SRC="${SRC:-dist/repo/aarch64}"
BRANCH="${BRANCH:-gh-pages}"
SIGNER="${MOARCHY_SIGNING_FPR:-}"

[[ -d $SRC ]] || { echo "no repo at $SRC -- run packaging/repo-add.sh first" >&2; exit 1; }
[[ -f "$SRC/$REPO.db.tar.gz" ]] || { echo "no $REPO.db.tar.gz in $SRC" >&2; exit 1; }

if [[ -z $SIGNER ]]; then
  echo "set MOARCHY_SIGNING_FPR to the fingerprint that signs this repo." >&2
  echo "secret keys on this machine:" >&2
  gpg --list-secret-keys --with-colons --fingerprint 2>/dev/null |
    awk -F: '/^sec/{s=1} /^fpr/&&s{f=$10; s=0} /^uid/&&f{print "  " f "  " $10; f=""}' >&2
  exit 1
fi
gpg --list-secret-keys "$SIGNER" >/dev/null 2>&1 || {
  echo "no secret key for $SIGNER in this keyring" >&2; exit 1; }

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
site="$stage/aarch64"
mkdir -p "$site"

# -L, so a symlink arrives as the file it points at. See (2) above.
cp -RL "$SRC/." "$site/"

# Sign the database and the file list, and then again under the names pacman
# actually fetches -- `moarchy-apps.db`, not `moarchy-apps.db.tar.gz`. They are
# the same bytes, so one signature covers both, but the request is for the short
# name and so is the request for its signature.
for base in db files; do
  target="$site/$REPO.$base.tar.gz"
  [[ -f $target ]] || continue
  rm -f "$target.sig"
  gpg --batch --yes --detach-sign --no-armor --local-user "$SIGNER" "$target"
  cp "$target" "$site/$REPO.$base"
  cp "$target.sig" "$site/$REPO.$base.sig"
done

gpg --export --armor "$SIGNER" > "$site/$REPO.gpg"
fpr=$(gpg --list-keys --with-colons "$SIGNER" | awk -F: '/^fpr/{print $10; exit}')

cat > "$stage/index.html" <<HTML
<!doctype html>
<meta charset="utf-8">
<title>[$REPO] pacman repository</title>
<h1>[$REPO]</h1>
<p>A signed pacman repository for <a href="https://github.com/SimonSchubert/moarchy-apps">moarchy-apps</a>.</p>
<pre>
# /etc/pacman.conf
[$REPO]
SigLevel = Required TrustedOnly
Server = https://simonschubert.github.io/moarchy-apps/aarch64

# trust the key that signs it
curl -O https://simonschubert.github.io/moarchy-apps/aarch64/$REPO.gpg
sudo pacman-key --add $REPO.gpg
sudo pacman-key --lsign-key $fpr
</pre>
<p>Key fingerprint: <code>$fpr</code></p>
HTML
# Pages runs Jekyll by default, which skips files beginning with an underscore
# and rewrites what it feels like. This is a package mirror, not a site.
touch "$stage/.nojekyll"

git worktree remove --force "$stage/wt" 2>/dev/null || true
if git show-ref --quiet "refs/heads/$BRANCH"; then
  git worktree add --quiet "$stage/wt" "$BRANCH"
else
  git worktree add --quiet --detach "$stage/wt"
  git -C "$stage/wt" checkout --orphan "$BRANCH"
  git -C "$stage/wt" rm -rqf . 2>/dev/null || true
fi

rm -rf "${stage:?}/wt/aarch64"
cp -R "$site" "$stage/wt/aarch64"
cp "$stage/index.html" "$stage/wt/index.html"
cp "$stage/.nojekyll" "$stage/wt/.nojekyll"

git -C "$stage/wt" add -A
if git -C "$stage/wt" diff --cached --quiet; then
  echo "nothing changed"
else
  git -C "$stage/wt" commit -qm "[$REPO] $(cd "$site" && ls -1 *.pkg.tar.* 2>/dev/null | grep -v '\.sig$' | tr '\n' ' ')"
  echo "committed to $BRANCH"
fi
git worktree remove --force "$stage/wt"

echo
echo "signed by $fpr"
echo "push it with:  git push origin $BRANCH"
