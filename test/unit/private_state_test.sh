#!/bin/sh
# Literal shell-looking fixture bytes must never expand.
# shellcheck disable=SC2016
set -eu
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
helper=root/usr/share/monkey-business/private-state.uc
mkdir "$T/state"
printf original > "$T/target"
ln -s "$T/target" "$T/state/value"
if printf changed | ucode "$helper" write "$T/state/value"; then echo 'symlink state accepted'; exit 1; fi
[ "$(cat "$T/target")" = original ]
rm "$T/state/value"
printf foreign > "$T/state/value"
chown 65534 "$T/state/value"
if printf changed | ucode "$helper" write "$T/state/value"; then echo 'foreign state accepted'; exit 1; fi
rm "$T/state/value"
printf 'synthetic $(never-execute)' | ucode "$helper" write "$T/state/value"
ucode -e 'let fs=require("fs"),s=fs.lstat(ARGV[0]); exit(s.uid == 0 && (s.mode & 0o777) == 0o600 && fs.readfile(ARGV[0]) == "synthetic $(never-execute)\n" ? 0 : 1);' "$T/state/value"
mkdir "$T/unsafe"
chmod 777 "$T/unsafe"
if ucode "$helper" dir "$T/unsafe/child"; then echo 'writable ancestor accepted'; exit 1; fi
echo 'PASS: private legacy state rejects symlinks, foreign ownership and writable ancestors'
