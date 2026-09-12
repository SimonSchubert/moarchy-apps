#!/bin/bash
# Build one app's release tarball from a tag.
#
#   packaging/release.sh habits 0.1.0
#
# This is the piece that makes a monorepo work with per-app PKGBUILDs. The
# tarball a PKGBUILD pins by checksum has to contain one app and the shared
# code it uses, and nothing else -- so it is assembled from two subtrees of the
# same tag rather than being the whole repo:
#
#   git archive <tag>:apps/<app>   -> moarchy_<app>/, data/, tests/, PKGBUILD
#   git archive <tag>:shared       -> moarchy_ui/
#
# The result is self-contained: no submodule, no runtime dependency between
# apps, and each app keeps its own version. `git archive` of a subtree at a tag
# is what buys that, and it is the reason one repo does not mean one version
# number.
#
# Deliberately NOT GitHub's auto-generated archive: those are produced on
# demand, and a change to the compression GitHub uses has broken every checksum
# pinned against them before. Upload this file as a release asset; an uploaded
# file is stored verbatim and its checksum cannot move under us.
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:?usage: release.sh <app> <version>}"
version="${2:?usage: release.sh <app> <version>}"
tag="${3:-$app-v$version}"
name="moarchy-$app"
out="${OUT:-dist}"

git rev-parse -q --verify "$tag^{tag}" >/dev/null 2>&1 || \
  git rev-parse -q --verify "$tag" >/dev/null || {
    echo "no such tag: $tag" >&2; exit 1; }

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
root="$stage/$name-$version"
mkdir -p "$root"

git archive "$tag:apps/$app" | tar x -C "$root"
git archive "$tag:shared"    | tar x -C "$root"

# The screenshots are for the repository's README, not for the package. They are
# the bulk of the download -- Keep's are half a megabyte -- and the PKGBUILD
# installs neither them nor the relative links in README.md that point at them,
# so they would travel to every machine that installs this and be read by none.
rm -rf "$root/docs"

# And the PKGBUILD, which must not travel inside the tarball it names. Its
# sha256sums line is the checksum of this archive; if the archive contains the
# PKGBUILD, then writing the checksum into it changes the archive, which changes
# the checksum. Two builds either side of pinning it produced two different
# hashes and the cycle had no fixed point. makepkg gets the PKGBUILD from the
# AUR repository, never from the source, so it has no business being here.
rm -f "$root/PKGBUILD" "$root/.SRCINFO"
# LICENSE lives once, at the top of the repo, and every package needs a copy.
git show "$tag:LICENSE"  > "$root/LICENSE"
git show "$tag:ruff.toml" > "$root/ruff.toml"

mkdir -p "$out"

# Build the same bytes every time. Two runs of this script a second apart used to
# produce two different checksums, because tar records mtimes and gzip stamps the
# time into its header -- which is the same class of problem the PKGBUILD warns
# about in GitHub's generated archives, arriving from our own side instead.
# Every file is stamped with the tag's own commit date, and gzip -n is told to
# write neither a name nor a timestamp.
# The stamp is the tag's own commit date, which makes the tarball a function
# of the tag and nothing else -- but it also means MOVING a tag changes the
# bytes. So pin the checksum *after* the tag is final, and do not re-tag
# afterwards. The commit that writes sha256sums into the PKGBUILD comes after
# the tag and is not part of it, which is fine: PKGBUILD is excluded above.
stamp=$(git log -1 --format=%cd --date=format:%Y%m%d%H%M.%S "$tag")
find "$root" -exec touch -t "$stamp" {} +
tar cf - -C "$stage" "$name-$version" | gzip -n -9 > "$out/$name-$version.tar.gz"

sum=$(shasum -a 256 "$out/$name-$version.tar.gz" | cut -d' ' -f1)
echo "$out/$name-$version.tar.gz"
echo "sha256  $sum"
echo
echo "put that in apps/$app/PKGBUILD, then upload the tarball as the v$version asset."
