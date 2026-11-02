#!/bin/sh
# Manual capture only. Supply the URL on stdin; credentials never enter curl argv.
set -eu
umask 077
[ "$#" = 0 ] || { echo 'Supply the subscription URL on stdin, without command-line arguments.' >&2; exit 2; }
mode=''
if [ -t 0 ]; then
	printf 'Subscription URL: ' >&2
	mode=$(stty -g)
	stty -echo
fi
trap '[ -z "$mode" ] || stty "$mode"' EXIT INT TERM
IFS= read -r URL
[ -z "$mode" ] || { stty "$mode"; mode=''; printf '\n' >&2; }
work=$(mktemp -d)
OUT="${MB_CAPTURE_OUT:-$work/subscription.raw}"
# An open exclusive descriptor prevents both pre-existing symlinks and path swaps.
set -C
exec 3>"$OUT"
set +C
printf '%s' "$URL" | python3 -c '
import json, sys
url = sys.stdin.read(8193)
if len(url) > 8192 or not url.lower().startswith("https://") or any(ord(c) <= 32 or ord(c) == 127 for c in url):
    sys.exit(1)
print("url = " + json.dumps(url, ensure_ascii=False))
' | curl --disable --globoff -fsSL --config - --proto '=https' --proto-redir '=https' \
	--max-redirs 5 --max-time 25 --max-filesize 2097152 --output /dev/fd/3
exec 3>&-
printf 'Saved private raw subscription to %s. Sanitize credentials before using it as a fixture.\n' "$OUT"
