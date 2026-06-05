#!/bin/sh
# Раннер netns-интеграционных тестов. Запускается в привилегированном Linux-контейнере
# (make test-integ). Каждый *.sh кроме run.sh — отдельный тест, exit!=0 = провал.
set -u

if [ "$(id -u)" != "0" ]; then
	echo "integ tests require root/privileged container" >&2
	exit 2
fi

fail=0
count=0
for f in test/integ/*.sh; do
	case "$f" in
		*/run.sh) continue ;;
	esac
	[ -e "$f" ] || continue
	count=$((count + 1))
	printf '\n=== %s ===\n' "$f"
	if sh "$f"; then
		echo "PASS: $f"
	else
		echo "FAIL: $f"
		fail=1
	fi
done

printf '\n%d integ test(s) run\n' "$count"
exit "$fail"
