#!/bin/sh
# Линт: shellcheck по shell-скриптам + ucode syntax.
set -u

rc=0

echo "== shellcheck =="
sh_found=0
while IFS= read -r f; do
	[ -n "$f" ] || continue
	sh_found=$((sh_found + 1))
	if ! shellcheck -x "$f"; then
		rc=1
	fi
done <<EOF
$(find scripts test root -name '*.sh' 2>/dev/null | sort)
EOF
[ "$rc" -eq 0 ] && echo "shellcheck: ok ($sh_found files)"

echo "== ucode syntax =="
if ! sh scripts/check-syntax.sh; then
	rc=1
fi

echo "== js syntax =="
if ! sh scripts/check-js.sh; then
	rc=1
fi

exit "$rc"
