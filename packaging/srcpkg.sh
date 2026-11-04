#!/bin/bash
# The corresponding source of an app's package: makepkg --allsource.
#
#   packaging/srcpkg.sh habits            # -> packages/moarchy-habits-0.2.0-1.src.tar.gz
#   packaging/srcpkg.sh queens puzzle-games
#
# Every binary package this repo publishes -- [market-apps] on gh-pages, and the
# copies moarchy's `repo` release carries -- has its source published beside
# it, as <pkgbase>-<ver>-<rel>.src.tar.gz: the PKGBUILD, every local file in
# its source=() (queens' runner, puzzle-games' patch) and every source it
# downloads (the release tarball, by its pinned checksum; an upstream clone at
# its pinned commit). That is what `makepkg --allsource` makes, and it is the
# whole point of doing it with makepkg rather than by hand: the file is exactly
# what the recipe builds from, verified by the recipe's own checksums.
# packaging/publish-market.sh runs this for any package that has no source
# beside it, and refuses to publish one that still has none.
#
# The release tarball is taken from dist/ when packaging/release.sh left it
# there, so nothing is downloaded that is already on disk; makepkg checks it
# against sha256sums either way, so a dist/ copy that is not the published
# asset is refused rather than packed.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="${IMAGE:-menci/archlinuxarm:base-devel}"
OUT="${OUT:-packages}"
[[ $# -gt 0 ]] || { echo "usage: srcpkg.sh <app>..." >&2; exit 1; }
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

for app in "$@"; do
  dir=apps/$app
  [[ -f $dir/PKGBUILD ]] || { echo "no such app: $app" >&2; exit 1; }
  name=$(sed -n 's/^pkgname=//p' "$dir/PKGBUILD" | head -1)
  ver=$(sed -n 's/^pkgver=//p' "$dir/PKGBUILD" | head -1)

  stage=$(mktemp -d)
  # The app's directory, links resolved, as makepkg would find it beside the
  # PKGBUILD in an AUR clone -- only what source=() names ends up in the file.
  cp -RL "$dir/." "$stage/"
  rm -rf "$stage/docs"
  for f in dist/"$name-$ver".tar.gz dist/moarchy-"$app-$ver".tar.gz; do
    [[ -f $f ]] && cp "$f" "$stage/"
  done

  echo "==> $app: makepkg --allsource"
  docker run --rm --platform linux/arm64 -v "$stage:/stage:ro" -v "$OUT:/out" \
    "$IMAGE" bash -euo pipefail -c '
      sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf
      # git for a git+ source; nothing else is installed, --allsource does not
      # build.
      pacman -Sy --noconfirm --needed git >/dev/null
      useradd -m build
      install -d -o build /work /work/srcpkg
      cp -a /stage/. /work/
      chown -R build /work
      su build -c "cd /work && SRCPKGDEST=/work/srcpkg makepkg --allsource --nodeps --noconfirm" >/work/log 2>&1 ||
        { tail -20 /work/log; exit 1; }
      cp /work/srcpkg/*.src.tar.* /out/
      ls /work/srcpkg
    ' | sed 's/^/    /'
  rm -rf "$stage"
done
