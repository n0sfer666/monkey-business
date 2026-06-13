#!/bin/sh
# ucode syntax check (types-эквивалент) для всех .uc.
# loadfile в module-режиме компилирует файл (включая export/import) без выполнения
# и бросает на синтаксической ошибке.
set -u

rc=0
found=0
while IFS= read -r f; do
	[ -n "$f" ] || continue
	found=$((found + 1))
	if ! ucode -e "loadfile('$f', { raw_mode: false });" 2>/tmp/uc-err; then
		echo "SYNTAX ERROR: $f"
		cat /tmp/uc-err
		rc=1
	fi
done <<EOF
$(find src test luci root -name '*.uc' 2>/dev/null | sort)
EOF

if [ "$rc" -eq 0 ]; then
	echo "ucode syntax: ok ($found files)"
fi
exit "$rc"
