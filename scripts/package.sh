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
# still a real pacman package, so pacman owns every file it places.
#
# The source tree is laid out the way packaging/release.sh lays out a tarball:
# the app, with the kit link resolved into a copy of shared/kit and without its
# screenshots, and LICENSE. check() runs, so the tests gate the package here as
# they do on the AUR.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?usage: package.sh <app>}"
DIR="$REPO/apps/$APP"
[[ -f $DIR/PKGBUILD ]] || { echo "no such app: $APP" >&2; exit 1; }
[[ -f $DIR/Panel.qml ]] || { echo "$APP is not a Quickshell app; its PKGBUILD builds from upstream" >&2; exit 1; }
NAME=$(sed -n 's/^pkgname=//p' "$DIR/PKGBUILD" | head -1)
VER=$(sed -n 's/^pkgver=//p' "$DIR/PKGBUILD" | head -1)
IMAGE="${IMAGE:-menci/archlinuxarm:base-devel}"
OUT="$REPO/packages"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME-$VER"
cp -RL "$DIR/." "$STAGE/$NAME-$VER/"
rm -rf "$STAGE/$NAME-$VER/docs" "$STAGE/$NAME-$VER/kit/tests" "$STAGE/$NAME-$VER/PKGBUILD" "$STAGE/$NAME-$VER/.SRCINFO"
find "$STAGE" -name __pycache__ -prune -exec rm -rf {} +
cp "$REPO/LICENSE" "$STAGE/$NAME-$VER/LICENSE"

mkdir -p "$OUT"
docker run --rm --platform linux/arm64 \
  -v "$STAGE:/stage:ro" -v "$DIR/PKGBUILD:/PKGBUILD:ro" -v "$OUT:/out" \
  "$IMAGE" bash -euo pipefail -c '
    # Docker Desktop cannot give pacman the Landlock sandbox it wants.
    sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf
    # qmltestrunner for check(); the rest of depends is not needed to build.
    pacman -Sy --noconfirm --needed qt6-declarative >/dev/null
    useradd -m build
    install -d -o build /work/src
    cd /work
    # The real PKGBUILD, with the parts that reach for a release asset taken out.
    sed -e "/^source=/d" -e "/^sha256sums=/d" /PKGBUILD > PKGBUILD
    cp -a /stage/. src/
    chown -R build /work
    su build -c "makepkg --noextract --noconfirm --nodeps"
    cp /work/*.pkg.tar.* /out/
  '
ls -la "$OUT/$NAME"-*.pkg.tar.* 2>/dev/null || { echo "no package produced" >&2; exit 1; }
