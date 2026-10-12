#!/bin/sh
set -u

SELF_DIR=$(dirname "$0")
# shellcheck source=root/usr/share/monkey-business/wdlock.sh disable=SC1091
. "$SELF_DIR/../../root/usr/share/monkey-business/wdlock.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "  FAIL $1: ждали '$3', получили '$2'"; fi; }
yn() { if "$@"; then echo y; else echo n; fi; }
held() { if [ -d "$1.d" ]; then echo y; else echo n; fi; }

mkdir "$T/lock.d"
eq "fresh.busy" "$(yn wd_lock_dir "$T/lock")" "n"
touch -t 200001010000 "$T/lock.d"
eq "stale.taken" "$(yn wd_lock_dir "$T/lock")" "y"
eq "stale.renewed" "$(yn [ "$(( $(date +%s) - $(stat -c %Y "$T/lock.d") ))" -lt 60 ])" "y"
rmdir "$T/lock.d"

mkdir "$T/nobin"
for c in mkdir rmdir sleep stat date; do ln -s "$(command -v "$c")" "$T/nobin/$c"; done

( PATH="$T/nobin" wd_lock "$T/m/lock" ) >/dev/null 2>&1
eq "exit.released" "$(held "$T/m/lock")" "n"

( PATH="$T/nobin" wd_lock "$T/m/lock" && : >"$T/m/ready"; sleep 10 & wait $! ) >/dev/null 2>&1 &
pid=$!
n=0
while [ ! -e "$T/m/ready" ] && [ "$n" -lt 30 ]; do sleep 0.1; n=$((n + 1)); done
eq "term.held" "$(held "$T/m/lock")" "y"
eq "term.busy" "$( (PATH="$T/nobin" yn wd_lock "$T/m/lock") 2>/dev/null)" "n"
kill -TERM "$pid"
wait "$pid" 2>/dev/null
eq "term.released" "$(held "$T/m/lock")" "n"

if command -v flock >/dev/null 2>&1; then
	( exec 9>"$T/f"; flock -n 9 && exec sleep 10 ) &
	holder=$!
	sleep 1
	eq "flock.busy" "$( (yn wd_lock "$T/f" 1) 2>/dev/null)" "n"
	kill "$holder"; wait "$holder" 2>/dev/null
	eq "flock.free" "$( (yn wd_lock "$T/f") 2>/dev/null)" "y"
fi

printf 'wdlock_test: %d ok, %d fail\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
