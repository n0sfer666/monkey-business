#!/bin/sh
# ucode syntax check (types-эквивалент) для всех модулей src/ и luci/.
#
# Раньше тут был `loadfile(f, { raw_mode: false })`, и он НЕ ПРОВЕРЯЛ НИЧЕГО: в этом режиме файл
# разбирается как шаблон, весь код остаётся литеральным текстом. Проверено — `function f( {`
# проходил с rc=0. Компилируем по-настоящему: одноразовый драйвер импортирует модуль, а значит
# компилятор разбирает и его собственные импорты (несуществующий модуль/имя = ошибка тут, а не
# на устройстве).
#
# test/*.uc не здесь: их целиком исполняет run-unit.sh. Плагин rpcd (абсолютные импорты + uci)
# грузится в test/unit/plugin_load_test.sh — ему нужна разложенная в /usr/share установка.
set -u

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

rc=0
found=0
while IFS= read -r f; do
	[ -n "$f" ] || continue
	found=$((found + 1))
	printf 'import * as m from "%s/%s";\n' "$(pwd)" "$f" > "$T/driver.uc"
	if ! ucode "$T/driver.uc" 2>"$T/err"; then
		echo "SYNTAX ERROR: $f"
		cat "$T/err"
		rc=1
	fi
done <<EOF
$(find src luci -name '*.uc' 2>/dev/null | sort)
EOF

if [ "$rc" -eq 0 ]; then
	echo "ucode syntax: ok ($found files)"
fi
exit "$rc"
