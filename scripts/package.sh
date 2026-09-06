#!/bin/bash
# Build an installable package from the working tree.
#
#   ./scripts/package.sh            # -> packages/moarchy-keep-*-any.pkg.tar.zst
#
# aur/moarchy-keep-git/PKGBUILD is a -git package: it clones the published
# repository, which is the right thing for someone installing this from the AUR
# and the wrong thing for testing a change that is not pushed anywhere. There is
# deliberately only one PKGBUILD in this repo -- the one the AUR publishes -- so
# what is tested here cannot drift from what people install. This builds the
# same package from the files as they are on disk, so what goes onto the phone
# is what is in front of you -- and it is still a real pacman package, so
# pacman owns every file it places, which is the rule the phone's own docs set.
#
# arch=any and pure Python, so nothing compiles and the container is only here
# to provide makepkg.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-menci/archlinuxarm:base-devel}"
OUT="$REPO/packages"

mkdir -p "$OUT"
docker run --rm --platform linux/arm64 \
  -v "$REPO:/tree:ro" -v "$OUT:/out" "$IMAGE" bash -euo pipefail -c '
    # Docker Desktop cannot give pacman the Landlock sandbox it wants.
    sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf
    useradd -m build
    install -d -o build /work
    cd /work

    # The real PKGBUILD, with the parts that reach for a git remote taken out.
    # Everything that decides what lands where -- the private module directory,
    # the desktop entry, the icon -- is the file in the repo, not a copy of it,
    # so this cannot drift from what the published package installs.
    sed -e "/^source=/d" -e "/^sha256sums=/d" -e "/^makedepends=/d" \
        -e "s|^pkgname=moarchy-keep-git$|pkgname=moarchy-keep|" \
        -e "/^pkgver() {/,/^}/d" \
        -e "s|cd \"\$srcdir/\$_pkgname\"|cd \"\$srcdir\"|" \
        /tree/aur/moarchy-keep-git/PKGBUILD > PKGBUILD
    mkdir -p src
    cp -a /tree/moarchy_keep /tree/bin /tree/data /tree/tests /tree/LICENSE /tree/README.md src/
    find src -name __pycache__ -prune -exec rm -rf {} +
    chown -R build /work

    su build -c "makepkg --noextract --noconfirm --nodeps" 
    cp /work/*.pkg.tar.* /out/
  '
ls -la "$OUT"/*.pkg.tar.* 2>/dev/null || { echo "no package produced" >&2; exit 1; }
