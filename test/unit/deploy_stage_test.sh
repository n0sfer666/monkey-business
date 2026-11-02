#!/bin/sh
# Actual tar semantics on the test platform, without SSH or touching device paths.
set -eu
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/source/etc/config" "$T/source/usr" "$T/destination/etc/config"
printf packaged > "$T/source/etc/config/monkey-business"
printf update > "$T/source/usr/file"
printf synthetic-original > "$T/destination/etc/config/monkey-business"
tar -C "$T/source" -czf "$T/archive.tgz" ./etc ./usr
# Fault after partial installation: source configuration is excluded, not restored
# from a temporary copy that error cleanup could destroy.
printf './etc/config/monkey-business\n' > "$T/excludes"
for extractor in tar 'busybox tar'; do
 rm -f "$T/destination/usr/file"
 printf synthetic-original > "$T/destination/etc/config/monkey-business"
 # Exercise both the normal test tar and BusyBox's portable short-option API.
 # shellcheck disable=SC2086
 if ($extractor -C "$T/destination" -X "$T/excludes" -xzf "$T/archive.tgz"; exit 1); then exit 1; fi
 [ "$(cat "$T/destination/etc/config/monkey-business")" = synthetic-original ]
 [ "$(cat "$T/destination/usr/file")" = update ]
done
echo 'PASS: failed extraction preserves the original UCI bytes without a temporary backup'
