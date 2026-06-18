#!/bin/sh
# Прогон всех ucode unit/snapshot тестов. Каждый файл — отдельный процесс ucode
# (чистое состояние харнесса), exit-код != 0 при любом упавшем файле.
set -u

fail=0
count=0
for f in test/unit/*.uc; do
	[ -e "$f" ] || continue
	count=$((count + 1))
	printf '\n=== %s ===\n' "$f"
	if ! ucode "$f"; then
		fail=1
	fi
done

for f in test/unit/*_test.sh; do
	[ -e "$f" ] || continue
	count=$((count + 1))
	printf '\n=== %s ===\n' "$f"
	if ! sh "$f"; then
		fail=1
	fi
done

printf '\n%d test file(s) run\n' "$count"
exit "$fail"
