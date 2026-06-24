# План: Watchdog reconnect-first стратегия

Спека: `.context/specs/2026-06-23-watchdog-reconnect-strategy.md`

## Task 1 — Liveness-проба + редкая exit-сверка
**Файл:** `root/usr/share/monkey-business/watchdog.sh`
- Добавить константу `LIVE_URLS='https://1.1.1.1 https://8.8.8.8'` и параметр
  `LIVE_TIMEOUT="${MB_WD_LIVE_TIMEOUT:-6}"`, `EXIT_EVERY="${MB_WD_EXIT_EVERY:-5}"`.
- `live_probe()`: перебор `LIVE_URLS`, `curl -s -4 -o /dev/null -x socks5h://$SOCKS --max-time
  $LIVE_TIMEOUT "$u"`; возврат 0 при первом успешном (`$? = 0`), иначе 1.
- `health_check(force)`: `live_probe || return 1`; затем `WD_EXITDUE=$((WD_EXITDUE+1))`; если
  `force=1` или `WD_EXITDUE >= EXIT_EVERY` → `WD_EXITDUE=0`, `refresh_home`,
  `res=$(eval_exit "$(vpn_probe "$TIMEOUT")")`; `ok` → `WD_BASE_IP=...`, return 0; иначе return 1.
  Иначе (exit не due) → return 0.
- `vpn_probe`/`direct_probe`/`eval_exit`/`refresh_home`/`extract_ip`/`probe_via` — не трогать.
**Зависимости:** нет. **Проверка:** T1 `make lint && make check`.

## Task 2 — Reconnect через procd-respawn
**Файл:** `root/usr/share/monkey-business/watchdog.sh`
- `RECONNECT_WAIT="${MB_WD_RECONNECT_WAIT:-5}"`.
- `vpn_reconnect()`: `kill $(pidof xray) 2>/dev/null || true; sleep "$RECONNECT_WAIT";
  vpn_running || vpn_start`. (procd респавнит; фолбэк — start, переприменит firewall.)
- НЕ использовать `$INIT restart` (flush снимает kill-switch).
**Зависимости:** нет. **Проверка:** T1.

## Task 3 — Машина состояний: reconnecting + net/vpn-различение
**Файл:** `root/usr/share/monkey-business/watchdog.sh`
- Параметры: `FAIL_LIMIT` дефолт → 3; `RECONNECT_LIMIT="${MB_WD_RECONNECT_LIMIT:-2}"`;
  `REC_TRIES="${MB_WD_REC_TRIES:-3}"`.
- `load_state`/`save_state`: добавить `WD_RECTRIES` (0), `WD_EXITDUE` (0).
- `tick` case: добавить ветку `reconnecting) tick_reconnecting ;;`.
- `tick_healthy`: заменить `vpn_probe`-логику на `health_check 0`:
  - ok → `WD_FAILS=0; WD_NEXT=$((t+POLL))`.
  - fail → `WD_FAILS++`; `< FAIL_LIMIT` → next POLL;
    `== FAIL_LIMIT` → если `direct_probe` пусто: `vpn_stop`, `WD_DOWNKIND=net`, лог "No
    connectivity...", `WD_PHASE=down`, `WD_FAILS=0`, next BACKOFF; иначе
    `WD_PHASE=reconnecting`, `WD_RECTRIES=0`, лог "VPN exit failing → reconnecting", `WD_NEXT=$t`.
- `tick_reconnecting()` (новая):
  - `direct_probe` пусто → `vpn_stop`, `WD_DOWNKIND=net`, лог "network down during reconnect",
    DOWN, backoff.
  - `vpn_reconnect`; цикл до `REC_TRIES`: `health_check 1` ok → лог "VPN reconnected (exit …)",
    `WD_PHASE=healthy`, `WD_FAILS=0; WD_RECTRIES=0`, next POLL, return; иначе `sleep 2`.
  - не ok → `WD_RECTRIES++`; `< RECONNECT_LIMIT` → next POLL; `== RECONNECT_LIMIT` → `vpn_stop`,
    `WD_DOWNKIND=vpn`, лог "Reconnect failed Nx, LAN on direct", DOWN, `WD_RECTRIES=0`, backoff.
- `tick_down`: заменить пробу на `health_check 1` (force exit-сверка в recovery), остальное как есть.
- Tag-смена в `tick`: дополнительно сбросить `WD_RECTRIES=0; WD_EXITDUE=0`.
- Проверить итог ≤ 200 строк; при превышении — вынести логику в helper без дублирования (DRY).
**Зависимости:** Task 1, 2. **Проверка:** T1 + ручной reasoning по переходам.

## Task 4 — Расширить юнит-тест
**Файл:** `test/unit/watchdog_test.sh`
- Моки: `live_probe() { [ -f "$T/live" ]; }` (наличие файла = liveness ok); `vpn_reconnect() {
  echo reconnect >> "$T/actions"; }`; очередь exit-IP остаётся `vpn_q` для `vpn_probe`.
- `reset`: создавать `$T/live` (liveness ok по умолчанию).
- Новые кейсы:
  - `reconnect.recover`: 3 фейла liveness (rm live) при живом direct → phase reconnecting; затем
    вернуть live + enq exit → phase healthy, в actions есть `reconnect`, нет `stop`.
  - `reconnect.failover`: reconnecting, reconnect не помогает RECONNECT_LIMIT раз → phase down,
    kind vpn, в actions `stop`, лог "Reconnect failed".
  - `healthy.netdown`: 3 фейла liveness + direct пусто → phase down, kind net, без `reconnect`.
  - `reconnecting.netdrop`: в reconnecting direct исчез → down, kind net.
  - `exit.leak.periodic`: liveness ok, но на EXIT_EVERY-цикле exit==home → fail-счётчик растёт.
  - Сохранить/адаптировать существующие 9 кейсов под новые дефолты (FAIL_LIMIT=3).
- Лог только на переходах (no-лог в healthy steady, no-лог между reconnect-попытками сверх входа).
**Зависимости:** Task 3. **Проверка:** T2 `make test-unit`.

## Task 5 — Обновить notes + verify-state
**Файлы:** `.context/notes/watchdog.md`, `.claude/.verify-state.json`
- notes: описать новую фазу reconnecting, liveness vs exit-сверку, reconnect через procd-respawn,
  новые параметры/дефолты, тайминг эскалации. Обновить раздел регресса (добавить 2026-06-23).
- verify-state: `{"tier":"T4",...,"checks":["lint","types","unit"],"result":"pass"}`.
**Зависимости:** Task 4 (после зелёных проверок). **Проверка:** —

## Definition of Done
- `make lint && make check && make test-unit` зелёные.
- Все DoD-пункты спеки выполнены (reconnect-тир, liveness, failover, net/vpn, лог на переходах).
- watchdog.sh ≤ 200 строк, shellcheck-чисто.
- notes обновлён, verify-state записан, коммит(ы) conventional.

## Проверки (по task)
| Task | Команда | Уровень |
|------|---------|---------|
| 1, 2, 3 | `make lint && make check` | T1 |
| 4 | `make test-unit` | T2/T4 |
| итог | `make lint && make check && make test-unit` | T4 |

## Коммиты (план)
- `feat(watchdog): reconnect-first strategy with cheap TCP liveness probe`
  (можно одним коммитом — изменения связаны; либо split watchdog.sh / test / docs).
