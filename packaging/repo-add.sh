#!/bin/bash
# Build the [moarchy] pacman repository from built packages.
#
#   packaging/repo-add.sh dist/*.pkg.tar.zst
#
# Why this exists
# ---------------
# moarchy-store installs through a helper that execs `pacman -S`, against an
# allowlist it reads from a root-owned, signed catalogue.toml. An AUR package
# is in no sync database, so the helper cannot install one at all -- which is
# why moarchy-keep sits in sweep/verdicts.toml as "AUR only, and ours", deferred
# from a store we wrote.
#
# The standing answer in that file is "if an AUR app matters, package it for the
# repos rather than weaken the allowlist". This is that, done literally. A
# signed binary repo IS a pacman sync database, so:
#
#   * the helper works unchanged -- it never asks which repo a package came
#     from, only whether the name is in the catalogue;
#   * the allowlist is untouched, so the security property the helper exists to
#     provide is exactly as narrow as before;
#   * the packages carry a signature from the same key that signs the
#     catalogue, which is stronger provenance than the AUR offers.
#
# What changes is one file in the image: /etc/pacman.conf gains a repo whose key
# is pinned. That is a decision made once, deliberately, rather than a hole.
#
# On the phone image
# ------------------
#   [moarchy]
#   SigLevel = Required TrustedOnly
#   Server = https://simonschubert.github.io/moarchy-apps/aarch64
#
# and the signing key installed into pacman's keyring:
#   pacman-key --add moarchy.gpg && pacman-key --lsign-key <fpr>
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${REPO:-moarchy}"
OUT="${OUT:-dist/repo/aarch64}"
KEY="${MOARCHY_SIGNING_KEY:-$HOME/.config/moarchy-store/signing-key.asc}"

[[ $# -gt 0 ]] || { echo "usage: repo-add.sh <package>.pkg.tar.zst ..." >&2; exit 1; }

mkdir -p "$OUT"
for pkg in "$@"; do
  [[ -f $pkg ]] || { echo "no such package: $pkg" >&2; exit 1; }
  cp "$pkg" "$OUT/"
done

# Sign each package. A repo whose packages are unsigned forces SigLevel to be
# relaxed on the device, which would give away the one thing this arrangement
# has over the AUR.
if [[ -f $KEY ]]; then
  for pkg in "$OUT"/*.pkg.tar.zst; do
    [[ -f "$pkg.sig" ]] && continue
    gpg --batch --yes --detach-sign --no-armor \
        --local-user "$(gpg --with-colons --import-options show-only --import "$KEY" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')" \
        "$pkg"
  done
else
  echo "warning: no signing key at $KEY -- packages are unsigned," >&2
  echo "         so the device would need SigLevel = Optional, which defeats the point." >&2
fi

# repo-add builds the sync database pacman downloads. -n refuses to add a
# package already in it at the same version, so a re-run is not a surprise.
repo-add --new --remove "$OUT/$REPO.db.tar.gz" "$OUT"/*.pkg.tar.zst

echo
echo "repo at $OUT"
ls -1 "$OUT" | sed 's/^/    /'
