#!/bin/sh
# Синтаксическая проверка LuCI client-side JS.
# LuCI-вьюхи — это тело функции (top-level return), поэтому валидируем через
# new Function(body): компилирует без выполнения, ловит синтаксис, не требует L/ui/rpc.
set -u

errors=$(mktemp)
trap 'rm -f "$errors"' EXIT
rc=0
found=0
while IFS= read -r f; do
	[ -n "$f" ] || continue
	found=$((found + 1))
	if ! node -e "new Function(require('fs').readFileSync(process.argv[1],'utf8'))" "$f" 2>"$errors"; then
		echo "JS SYNTAX ERROR: $f"
		cat "$errors"
		rc=1
	fi
done <<EOF
$(find luci scripts/ui-diff -name '*.js' 2>/dev/null | sort)
EOF

if [ "$rc" -eq 0 ]; then
	echo "js syntax: ok ($found files)"
fi
exit "$rc"
