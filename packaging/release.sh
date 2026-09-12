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
# LICENSE lives once, at the top of the repo, and every package needs a copy.
git show "$tag:LICENSE"  > "$root/LICENSE"
git show "$tag:ruff.toml" > "$root/ruff.toml"

mkdir -p "$out"
tar czf "$out/$name-$version.tar.gz" -C "$stage" "$name-$version"

sum=$(shasum -a 256 "$out/$name-$version.tar.gz" | cut -d' ' -f1)
echo "$out/$name-$version.tar.gz"
echo "sha256  $sum"
echo
echo "put that in apps/$app/PKGBUILD, then upload the tarball as the v$version asset."
