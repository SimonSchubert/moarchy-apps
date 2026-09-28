#!/usr/bin/env bash
# Draw an app's three store screens in every Omarchy theme, and put them into
# mobile-market-data for App Finder: a phone is shown the three drawn in its
# own theme.
#
#   packaging/publish-store.sh weather
#   packaging/publish-store.sh $(ls apps)      # every app recommended.json names
#
# The screens are the lines named store-* in apps/<app>/dev/shots, shot by
# scripts/app-shot.sh's themed mode in the moarchy-qml image, once per theme
# scripts/fetch-themes.sh fetches: the ones the phone ships. Each becomes a
# WebP named <pkg>-<n>-<first 8 of its sha256>, like every picture in the data
# repo, and the app's entry in aur/recommended.json gets
#
#   "themed": {"<theme>": [three names], ...}
#   "shots":  the tokyo-night three -- for a theme App Finder has none for, and
#             for an App Finder from before "themed"
#
# The shots are the same bytes on every run (app-shot.sh), so an app that did
# not change adds nothing to the data repo's history. Pictures of this app no
# longer named are deleted. This writes the checkout and commits nothing:
# look, then commit and push the data repo.
set -euo pipefail
cd "$(dirname "$0")/.."

DATA=${MARKET_DATA:-../mobile-market-data}
IMAGE=${IMAGE:-moarchy-qml}
FALLBACK=tokyo-night
[[ $# -gt 0 ]] || { echo "usage: publish-store.sh <app>..." >&2; exit 1; }
[[ -f $DATA/aur/recommended.json ]] || { echo "no $DATA/aur/recommended.json -- set MARKET_DATA" >&2; exit 1; }
command -v cwebp >/dev/null || { echo "no cwebp" >&2; exit 1; }

scripts/fetch-themes.sh .themes >/dev/null
[[ -f .themes/$FALLBACK/colors.toml ]] || { echo "no $FALLBACK among the themes" >&2; exit 1; }

for app in "$@"; do
  pkg=$(sed -n 's/^pkgname=//p' "apps/$app/PKGBUILD" 2>/dev/null | head -1)
  [[ -n $pkg ]] || { echo "no such app: $app" >&2; exit 1; }
  jq -e --arg p "$pkg" 'any(.[]; .pkg == $p)' "$DATA/aur/recommended.json" >/dev/null ||
    { echo "$pkg: not in recommended.json, skipped"; continue; }
  # In the order the file has them: the order App Finder's card turns through.
  mapfile -t names < <(sed -n 's/^shot \(store-[^ ]*\).*/\1/p' "apps/$app/dev/shots" 2>/dev/null)
  [[ ${#names[@]} -gt 0 ]] || { echo "$app: no store-* shots in dev/shots" >&2; exit 1; }

  out=.shots/$app-themed
  rm -rf "$out"
  echo "==> $app: ${#names[@]} screens in $(find .themes -name colors.toml | wc -l | tr -d ' ') themes"
  docker run --rm -v "$PWD:/src" -w /src -e THEMES=.themes "$IMAGE" \
    scripts/app-shot.sh "$app" "$out" >/dev/null

  themed=$out/themed.json
  echo '{}' >"$themed"
  for dir in "$out"/*/; do
    theme=$(basename "$dir")
    files=()
    for i in "${!names[@]}"; do
      png=$dir/${names[$i]}.png
      [[ -f $png ]] || { echo "$app: no $png" >&2; exit 1; }
      cwebp -quiet -q 80 "$png" -o "$out/tmp.webp"
      sum=$(shasum -a 256 "$out/tmp.webp" | cut -c1-8)
      name=$pkg-$i-$sum.webp
      [[ -f $DATA/aur/recommended/shots/$name ]] || cp "$out/tmp.webp" "$DATA/aur/recommended/shots/$name"
      files+=("$name")
    done
    jq --arg t "$theme" '. + {($t): $ARGS.positional}' "$themed" --args "${files[@]}" >"$themed.new"
    mv "$themed.new" "$themed"
  done
  rm -f "$out/tmp.webp"

  python3 - "$DATA/aur/recommended.json" "$pkg" "$themed" "$FALLBACK" <<'PY'
import json, sys
path, pkg, themed, fallback = sys.argv[1:]
entries = json.load(open(path))
themed = json.load(open(themed))
for e in entries:
    if e["pkg"] == pkg:
        e["shots"] = themed[fallback]
        e["themed"] = dict(sorted(themed.items()))
with open(path, "w") as f:
    f.write(json.dumps(entries, indent=1, ensure_ascii=False) + "\n")
PY

  # This app's pictures that nothing names any more.
  keep=$(jq -r --arg p "$pkg" '.[] | select(.pkg == $p) | (.shots[], (.themed // {} | .[][]))' "$DATA/aur/recommended.json" | sort -u)
  gone=0
  for f in "$DATA/aur/recommended/shots/$pkg"-[0-9]-*.webp; do
    [[ -f $f && ${f##*/} =~ ^$pkg-[0-9]+-[0-9a-f]{8}\.webp$ ]] || continue
    grep -qxF "${f##*/}" <<<"$keep" || { rm -f "$f"; gone=$((gone + 1)); }
  done
  echo "    $(sort -u <<<"$keep" | wc -l | tr -d ' ') pictures named, $gone old ones removed"
done
git -C "$DATA" status --short | awk '{print $1}' | sort | uniq -c | sed 's/^/    /'
