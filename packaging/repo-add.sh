#!/bin/bash
# Build the [moarchy] pacman repository from built packages.
#
#   packaging/repo-add.sh packages/*.pkg.tar.*
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

[[ $# -gt 0 ]] || { echo "usage: repo-add.sh <package>.pkg.tar.* ..." >&2; exit 1; }

mkdir -p "$OUT"
for pkg in "$@"; do
  [[ -f $pkg ]] || { echo "no such package: $pkg" >&2; exit 1; }
  cp "$pkg" "$OUT/"
done

# Whatever compression the packages actually use. Upstream Arch defaults to
# zstd and Arch Linux ARM's makepkg.conf still says `PKGEXT='.pkg.tar.xz'`, so
# a script that globbed for one of them found nothing on the machine that
# builds for the phone -- it copied the packages in, signed none of them, and
# handed repo-add an empty list. pacman reads either, and so does repo-add;
# only this file had an opinion.
shopt -s nullglob
packages=()
for pkg in "$OUT"/*.pkg.tar.*; do
  [[ $pkg == *.sig ]] || packages+=("$pkg")
done
shopt -u nullglob
[[ ${#packages[@]} -gt 0 ]] || { echo "no packages in $OUT" >&2; exit 1; }

# Sign each package. A repo whose packages are unsigned forces SigLevel to be
# relaxed on the device, which would give away the one thing this arrangement
# has over the AUR -- so an unsignable repo is not built at all unless the
# caller says out loud that it wants one.
signer=""
if [[ -f $KEY ]]; then
  signer=$(gpg --with-colons --import-options show-only --import "$KEY" 2>/dev/null |
           awk -F: '/^fpr/{print $10; exit}')
  # The key file holding the secret material is not the same as the secret
  # material being usable: gpg signs with what is in the keyring, and a key
  # sitting in a config directory has not been imported into one. Asked here,
  # once, because the alternative is `gpg: signing failed: No secret key` from
  # inside a loop after the packages have already been copied.
  if ! gpg --list-secret-keys "$signer" >/dev/null 2>&1; then
    echo "the key at $KEY is not in this keyring, so nothing can be signed with it." >&2
    echo "  its fingerprint:  $signer" >&2
    echo "  import it with:   gpg --import $KEY" >&2
    echo "  or point MOARCHY_SIGNING_KEY at the key you mean to sign packages with." >&2
    [[ ${ALLOW_UNSIGNED:-} == 1 ]] || exit 1
    signer=""
  fi
else
  echo "no signing key at $KEY." >&2
  [[ ${ALLOW_UNSIGNED:-} == 1 ]] || exit 1
fi

if [[ -n $signer ]]; then
  for pkg in "${packages[@]}"; do
    [[ -f "$pkg.sig" ]] && continue
    gpg --batch --yes --detach-sign --no-armor --local-user "$signer" "$pkg"
  done
  echo "signed by $signer"
else
  echo "warning: ALLOW_UNSIGNED=1 -- these packages are unsigned, so the device" >&2
  echo "         would need SigLevel = Optional, which defeats the point." >&2
fi

# repo-add builds the sync database pacman downloads. -n refuses to add a
# package already in it at the same version, so a re-run is not a surprise.
repo-add --new --remove "$OUT/$REPO.db.tar.gz" "${packages[@]}"

echo
echo "repo at $OUT"
ls -1 "$OUT" | sed 's/^/    /'
