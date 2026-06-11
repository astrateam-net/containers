#!/usr/bin/env bash
# Harvest the private @devolutions/icons assets out of the official gateway image.
#
# The stock webapp depends on @devolutions/icons (font + glyph CSS) from a private
# registry we cannot reach, so the build uses a stub (patch 0002). The real assets,
# however, ship INSIDE the official image we already base on. This populates the stub
# with them so `pnpm build` bundles the real icon font + glyph map — keeping repo and
# image byte-locked to one version.
#
# Dir-based variant (no docker daemon): the caller has already materialized the stock
# image's built webapp client/ on disk (in the Dockerfile via `COPY --from=<stock>
# /opt/devolutions/gateway/webapp/client`), and passes that directory.
#
# Usage: harvest-icons.sh <client-dir> <stub-dir>
#   client-dir : the stock image's /opt/devolutions/gateway/webapp/client tree
#   stub-dir   : .../webapp/stubs/icons   (populates dist/fonts + dist/scss)
set -euo pipefail

CLIENT="${1:?usage: harvest-icons.sh <client-dir> <stub-dir>}"
STUB="${2:?usage: harvest-icons.sh <client-dir> <stub-dir>}"

echo ">> harvesting @devolutions/icons from $CLIENT"

FONTS_SRC="$CLIENT/assets/fonts"
STYLES="$(ls "$CLIENT"/styles-*.css | head -1)"
[ -f "$STYLES" ] || { echo "!! no styles-*.css in $CLIENT" >&2; exit 1; }

# 1) Font files. eot/svg/ttf/woff ship under assets/fonts (unhashed, as the package
#    shipped them); woff2 only exists hashed under media/ — normalize its name.
mkdir -p "$STUB/dist/fonts"
for ext in eot svg ttf woff; do
  cp "$FONTS_SRC/devolutions-icons.$ext" "$STUB/dist/fonts/devolutions-icons.$ext"
done
woff2="$(ls "$CLIENT"/media/devolutions-icons-*.woff2 2>/dev/null | head -1)"
[ -n "$woff2" ] && cp "$woff2" "$STUB/dist/fonts/devolutions-icons.woff2"

# 2) The CSS the package ships in dist/scss: @font-face (urls relative to dist/scss →
#    ../fonts) + the glyph map. main.scss already forces font-family !important on
#    .dvl-icon, so only @font-face + the per-glyph content rules are needed here.
mkdir -p "$STUB/dist/scss"
CSS="$STUB/dist/scss/devolutions-icons.css"
{
  echo "/* devget: harvested from the stock gateway image by tools/harvest-icons.sh — real @devolutions/icons. Do not edit by hand. */"
  printf "@font-face{font-family:'devolutions-icons';"
  printf "src:url('../fonts/devolutions-icons.eot');"
  printf "src:url('../fonts/devolutions-icons.eot?#iefix') format('embedded-opentype'),"
  printf "url('../fonts/devolutions-icons.woff2') format('woff2'),"
  printf "url('../fonts/devolutions-icons.ttf') format('truetype'),"
  printf "url('../fonts/devolutions-icons.woff') format('woff'),"
  printf "url('../fonts/devolutions-icons.svg#devolutions-icons') format('svg');"
  printf "font-weight:normal;font-style:normal}\n"
  # Every glyph mapping the compiled stylesheet carries, deduped, one per line.
  # Class names are MIXED-CASE (e.g. dvl-icon-entry-SampleInformation — 300+ entry-*
  # glyphs); a lowercase-only character class silently drops them.
  grep -oE '\.dvl-icon-[A-Za-z0-9_-]+::?before\{content:"[^"]*"\}' "$STYLES" | sort -u
} > "$CSS"

GLYPHS="$(grep -c 'content:' "$CSS" || true)"
echo ">> wrote $CSS ($GLYPHS glyph rules)"
echo ">> fonts: $(ls "$STUB/dist/fonts" | tr '\n' ' ')"
