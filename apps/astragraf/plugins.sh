#!/bin/sh
# usage: plugins.sh <plugins> <required> <arch> <out_dir> <public_pem> <list_out>
set -eu

PLUGINS="${1:?}"
REQUIRED="${2:?}"
ARCH="${3:?}"
OUT="${4:?}"
PEM="${5:?}"
LIST="${6:?}"

PRIOR_KEY=uJAXaOR2-CwuKz2xuj5jMOtj
API=https://grafana.com/api/plugins

die() {
	echo "plugins: FAIL: $*" >&2
	exit 1
}

mkdir -p "$OUT"

for entry in $(echo "$PLUGINS" | tr ',' ' '); do
	id=${entry%@*}
	ver=${entry#*@}
	[ "$ver" = "$entry" ] && ver=latest
	curl -fsSL -o /tmp/plugin.zip "$API/$id/versions/$ver/download?os=linux&arch=$ARCH" ||
		die "download $id@$ver ($ARCH)"
	unzip -qo /tmp/plugin.zip -d "$OUT" || die "unzip $id"
	rm -f /tmp/plugin.zip
	[ -f "$OUT/$id/plugin.json" ] || die "$id missing after unzip"
done

patched=""
for bin in $(find "$OUT" -type f -name 'gpx_*'); do
	grep -qaF "$PRIOR_KEY" "$bin" || continue
	dir=$(dirname "$bin")
	python "$(dirname "$0")/agent.py" "$bin" "$PEM" "$bin.new" || die "agent $bin"
	mv "$bin.new" "$bin"
	chmod 0755 "$bin"
	rm -f "$dir/MANIFEST.txt"
	patched="$patched $(basename "$dir")"
done

for id in $(echo "$REQUIRED" | tr ',' ' '); do
	case " $patched " in
	*" $id "*) ;;
	*) die "$id not patched" ;;
	esac
done

printf '%s\n' $patched | sort -u >"$LIST"
echo "plugins: OK ($(wc -l <"$LIST" | tr -d ' ') patched)"
