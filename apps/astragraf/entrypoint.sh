#!/bin/sh
# Copy the image's plugins into the live plugin directory, then hand over to the
# upstream entrypoint. Anything else in that directory is left alone.
set -eu

SEED=/opt/astragraf/plugins
LIST=/opt/astragraf/unsigned.txt
DEST="${GF_PATHS_PLUGINS:-/var/lib/grafana/plugins}"

if [ -d "$SEED" ]; then
	mkdir -p "$DEST"
	for dir in "$SEED"/*/; do
		[ -d "$dir" ] || continue
		rm -rf "$DEST/$(basename "$dir")"
		cp -a "${dir%/}" "$DEST/"
	done
fi

if [ -s "$LIST" ]; then
	ids=$(tr '\n' ',' <"$LIST" | sed 's/,$//')
	GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS="${GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS:+${GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS},}${ids}"
	export GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS
fi

exec /run.sh "$@"
