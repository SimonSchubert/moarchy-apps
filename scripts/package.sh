#!/bin/bash
# Build an installable package for one app from the working tree.
#
#   scripts/package.sh keep         # -> packages/moarchy-keep-*-any.pkg.tar.zst
#
# apps/<app>/PKGBUILD points at a published release asset, which is the right
# thing for someone installing this and the wrong thing for testing a change
# that is not pushed anywhere. There is deliberately only one PKGBUILD per app
# -- the one that is published -- so what is tested here cannot drift from what
# people install. This builds the same package from the files as they are on
# disk, so what goes onto the phone is what is in front of you -- and it is
# still a real pacman package, so pacman owns every file it places, which is
# the rule the phone's own docs set.
#
# arch=any and pure Python, so nothing compiles and the container is only here
# to provide makepkg.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?usage: package.sh <app>}"
[[ -d "$REPO/apps/$APP" ]] || { echo "no such app: $APP" >&2; exit 1; }
MODULE=$(basename "$(find "$REPO/apps/$APP" -maxdepth 1 -name 'moarchy_*' -type d)")
IMAGE="${IMAGE:-menci/archlinuxarm:base-devel}"
OUT="$REPO/packages"

mkdir -p "$OUT"
docker run --rm --platform linux/arm64 \
  -v "$REPO:/tree:ro" -v "$OUT:/out" -e APP="$APP" -e MODULE="$MODULE" \
  "$IMAGE" bash -euo pipefail -c '
    # Docker Desktop cannot give pacman the Landlock sandbox it wants.
    sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf
    useradd -m build
    install -d -o build /work
    cd /work

    # The real PKGBUILD, with the parts that reach for a git remote taken out.
    # Everything that decides what lands where -- the private module directory,
    # the desktop entry, the icon -- is the file in the repo, not a copy of it,
    # so this cannot drift from what the published package installs.
    sed -e "/^source=/d" -e "/^sha256sums=/d" \
        -e "s|cd \"\$srcdir/\$pkgname-\$pkgver\"|cd \"\$srcdir\"|" \
        "/tree/apps/$APP/PKGBUILD" > PKGBUILD
    mkdir -p src
    # The same two subtrees packaging/release.sh assembles a tarball from, so a
    # locally built package has exactly the layout the published one does --
    # including the vendored shared code the PKGBUILD installs.
    cp -a "/tree/apps/$APP/$MODULE" /tree/shared/moarchy_ui src/
    cp -a "/tree/apps/$APP/launcher" "/tree/apps/$APP/data" "/tree/apps/$APP/tests" src/
    cp -a "/tree/apps/$APP/README.md" /tree/LICENSE src/
    find src -name __pycache__ -prune -exec rm -rf {} +
    chown -R build /work

    su build -c "makepkg --noextract --noconfirm --nodeps" 
    cp /work/*.pkg.tar.* /out/
  '
ls -la "$OUT"/*.pkg.tar.* 2>/dev/null || { echo "no package produced" >&2; exit 1; }
