# Отчёт: watchdog reconnect-first стратегия (2026-06-23)

## Выполнено
- **Task 1** — `live_probe` (TLS-handshake через socks к 1.1.1.1/8.8.8.8) + `health_check(force)`
  с редкой exit-IP сверкой (`EXIT_EVERY`).
- **Task 2** — `vpn_reconnect` через `kill xray` + procd respawn (kill-switch держится).
- **Task 3** — машина состояний `healthy → reconnecting → down`, net vs vpn на лимите фейлов.
- **Task 4** — расширен `test/unit/watchdog_test.sh` (46 passed, 0 failed).
- **Task 5** — обновлён `.context/notes/watchdog.md`, записан `.verify-state.json` (T4/pass).

## Заблокировано
- Нет.

## Проверки
- `make lint` — ok (shellcheck 24 файла). `make check` — ok. `make test-unit` — ok (8 файлов).
- T4-регресс по новым переходам зелёный. T3 (железо) — при деплое (`make deploy`).

## Изменённые файлы
- `root/usr/share/monkey-business/watchdog.sh` (переписан, 200 строк)
- `root/usr/share/monkey-business/probes.sh` (новый, слой проб)
- `scripts/deploy-vm.sh` (ship probes.sh)
- `test/unit/watchdog_test.sh` (новые кейсы)
- `.context/notes/watchdog.md`, `.context/specs/2026-06-23-watchdog-reconnect-strategy.md`
- `.claude/plans/2026-06-23-watchdog-reconnect-strategy.md` (план, не закоммичен)

## Коммиты
- `3da9551 feat(watchdog): reconnect-first strategy with cheap TCP liveness probe`

## Деплой
- На устройство: `make deploy` (ship watchdog.sh + probes.sh + cron). probes.sh обязателен —
  watchdog.sh сорсит его; без него watchdog не стартует.
