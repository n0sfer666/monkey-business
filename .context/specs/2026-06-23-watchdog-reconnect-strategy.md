---
date: 2026-06-23
tags:
  - spec
  - watchdog
  - failover
status: approved
---

# Watchdog: reconnect-first стратегия + дешёвый liveness

## Контекст
`root/usr/share/monkey-business/watchdog.sh` детектит провал VPN и при kill_switch=1
делает `init.d stop` (LAN падает на direct), затем раз в 10 мин пробует поднять VPN.

Инцидент (повтор 2026-06-18): пользователь видит «связь пропала», вручную **переподключается**
(рестарт xray) — и всё работает. Значит watchdog ложно решает, что VPN мёртв, и сносит его на
direct, хотя лечится простым reconnect. Корневые причины:

1. **В HEALTHY watchdog никогда не перезапускает xray** (`vpn_running || vpn_start` — старт лишь
   если процесс мёртв). Типовой отказ Reality/VLESS — процесс жив, сессия/туннель сдохли. Watchdog
   не чинит туннель, а через 5 фейлов сносит на direct.
2. **Echo-IP проба хрупкая/бан-склонная**: `ipify/ifconfig.me/icanhazip` дёргаются каждые 60с с
   общего exit-IP. 429/таймаут/пустота → ложный «туннель упал».
3. **Liveness и leak-detection смешаны**: недоступность echo-сервиса трактуется как смерть VPN.

## Требования

### Функциональные
- **F1. Дешёвый liveness**: основная частая проба — TCP/TLS-handshake через socks5h к иностранному
  anycast-IP (`1.1.1.1:443`, фолбэк `8.8.8.8:443`). Успех = xray несёт трафик в туннель. Не банится
  (нет тела/rate-limit), не зависит от echo-сервиса. Цели обязаны быть proxied (foreign, не в direct).
- **F2. Редкая exit-IP сверка**: echo-IP проба (exit ≠ домашний) выполняется раз в `EXIT_EVERY`
  циклов (анти-бан) + принудительно при подтверждении recovery/reconnect. Ловит утечку direct.
- **F3. Reconnect-тир**: при `FAIL_LIMIT` фейлах подряд И живом direct — НЕ сразу на direct, а
  сначала `reconnect` (bounce xray, kill-switch держится). Помогло → HEALTHY.
- **F4. Reconnect через procd-respawn**: `kill xray` → procd респавнит процесс, firewall/kill-switch
  не трогаются (`init.d stop/restart` нельзя — `flush.sh` снимает kill-switch). Фолбэк `vpn_start`,
  если procd не поднял.
- **F5. Failover**: только после `RECONNECT_LIMIT` неудачных reconnect → `vpn_stop` (init.d stop →
  LAN на direct) → DOWN, длинный backoff, периодический recovery (как сейчас).
- **F6. Net vs VPN**: при `FAIL_LIMIT` фейлах, если direct мёртв → это локальный интернет:
  reconnect бессмыслен, сразу DOWN(net), ждём (как текущий net-kind).
- **F7. Лог только на переходах состояний** + ротация (сохранить текущее свойство).

### Нефункциональные
- POSIX sh, `set -u`, shellcheck-чистый. Файл ≤ 200 строк.
- Флэш-бережно: стейт в tmpfs, лог редкий.
- Идемпотентность, flock, все `curl` с `--max-time`.
- Env-override всех параметров (`MB_WD_*`) для детерминированных юнит-тестов.

## Архитектура

### Сигналы здоровья
- `live_probe()` — `curl -x socks5h://$SOCKS --max-time T -s -o /dev/null https://1.1.1.1`
  (фолбэк 8.8.8.8). Возврат 0 = handshake прошёл. Дёшево, небанируемо. Зовётся каждый tick.
- `vpn_probe()` (exit-IP через echo) + `direct_probe()` + `eval_exit` — **без изменений семантики**,
  но зовутся редко (раз в `EXIT_EVERY`, либо force в reconnect/recovery).
- `health_check(force)` — `live_probe` обязателен; exit-IP сверка когда `WD_EXITDUE>=EXIT_EVERY`
  или `force=1`. Утечка (exit==home) или невалидный exit при force → fail.

### Машина состояний
Фазы: `healthy → reconnecting → down` (+ обратно). Стейт-переменные добавляются:
`WD_RECTRIES`, `WD_EXITDUE` (счётчик до exit-сверки).

- **HEALTHY** (каждые `POLL`):
  - cold-start: `vpn_running || vpn_start`.
  - `health_check 0` ok → `WD_FAILS=0`, next=POLL.
  - fail → `WD_FAILS++`. `< FAIL_LIMIT` → next=POLL.
  - `== FAIL_LIMIT`: direct мёртв → `vpn_stop`, DOWN(net), backoff (F6).
    direct жив → фаза `reconnecting`, `WD_RECTRIES=0`, действовать сразу.
- **RECONNECTING** (каждые `POLL`):
  - direct умер meanwhile → `vpn_stop`, DOWN(net), backoff.
  - `vpn_reconnect` (kill→respawn) + до `REC_TRIES` быстрых `health_check 1` (force exit) с паузой.
  - ok → лог "VPN reconnected", HEALTHY, сброс счётчиков, next=POLL.
  - не ok → `WD_RECTRIES++`. `< RECONNECT_LIMIT` → next=POLL (ещё попытка).
    `== RECONNECT_LIMIT` → `vpn_stop`, лог "reconnect failed Nx → direct", DOWN(vpn), backoff.
- **DOWN** (каждые `BACKOFF`): без изменений по сути — direct мёртв → ждём (net); direct ожил →
  `vpn_start` + до `RECOVERY_TRIES` `health_check 1` → HEALTHY либо назад `vpn_stop`/DOWN(vpn).

### Параметры (дефолты боевые; env-override)
| Параметр | Дефолт | Смысл |
|----------|--------|-------|
| `MB_WD_FAIL_LIMIT` | 3 | liveness-фейлов подряд → reconnecting |
| `MB_WD_RECONNECT_LIMIT` | 2 | неудачных reconnect → failover на direct |
| `MB_WD_POLL` | 60 | интервал HEALTHY/RECONNECTING |
| `MB_WD_BACKOFF` | 600 | интервал DOWN |
| `MB_WD_EXIT_EVERY` | 5 | раз в N циклов сверять exit-IP (leak) |
| `MB_WD_REC_TRIES` | 3 | быстрых проб после reconnect |
| `MB_WD_RECOVERY_TRIES` | 5 | проб в DOWN-recovery |
| `MB_WD_TIMEOUT` | 10 | таймаут direct/exit пробы |
| `MB_WD_LIVE_TIMEOUT` | 6 | таймаут liveness |
| `MB_WD_REC_TIMEOUT` | 6 | таймаут проб в reconnect/recovery |
| `MB_WD_RECONNECT_WAIT` | 5 | пауза после kill xray (procd respawn) |

Тайминг при реальном обрыве туннеля (direct жив): 3 фейла (≈3 мин) → reconnect-тир →
2 reconnect-попытки (≈2 мин) → direct. Ложный одиночный блип liveness не двигает с HEALTHY.

## Edge cases
- **procd не респавнит** (порог respawn исчерпан) → `vpn_running || vpn_start` поднимет и
  переприменит firewall (идемпотентно).
- **Liveness ok, но leak** (exit==home) на exit-сверке → fail → reconnect (рестарт чинит routing).
- **1.1.1.1/8.8.8.8 в direct-листе** → liveness уйдёт мимо туннеля, дохлый туннель замаскируется.
  Митигация: цели иностранные (не geoip:ru), под bypass-RU всегда proxied; задокументировать.
- **Смена сервера (tag)** → сброс exit-baseline + счётчиков (сохранить текущее поведение).
- **Net умер во время reconnecting** → не зацикливаться: уходим в DOWN(net).
- **intent=0** → idle, стейт удаляется (без изменений).

## Риски и митигации
- Доп. фаза усложняет автомат → покрыть юнит-тестом все новые переходы (T4-регресс).
- Лишний шум в логе reconnect → логировать только вход в reconnecting и итог (ok/failover), не
  каждую попытку.
- `kill xray` гонка с procd → пауза `RECONNECT_WAIT` + проверка `vpn_running` + фолбэк start.

## Тестовая стратегия
- **T4 (регресс, обязательно)**: расширить `test/unit/watchdog_test.sh` — мок `live_probe`,
  `vpn_reconnect`; новые кейсы: HEALTHY→reconnecting→HEALTHY (reconnect помог),
  reconnecting→DOWN(vpn) (RECONNECT_LIMIT исчерпан + vpn_stop), HEALTHY→DOWN(net) (direct мёртв на
  лимите, без reconnect), net-умер-в-reconnecting→DOWN(net), liveness-fail-но-exit-не-due→fail-count,
  лог только на переходах. Сохранить все существующие кейсы зелёными.
- **T1**: `make lint` (shellcheck) + `make check`.
- **T2**: `make test-unit` зелёный.
- **T3 (на железе, делегируется пользователю при деплое)**: реальный обрыв туннеля → reconnect
  поднимает без падения на direct; убийство сервера → failover на direct; восстановление → HEALTHY.

## Definition of Done
- Новый автомат реализован в `watchdog.sh` (≤200 строк, shellcheck-чисто).
- Liveness через socks к иностранному IP; exit-IP сверка редкая (F1, F2).
- Reconnect-тир через procd-respawn без снятия kill-switch (F3, F4); failover после лимита (F5).
- net vs vpn-различение на лимите (F6); лог только на переходах (F7).
- `test/unit/watchdog_test.sh` расширён, `make lint && make check && make test-unit` зелёные.
- `.context/notes/watchdog.md` обновлён под новую стратегию.
- `.claude/.verify-state.json` записан (T4/pass).
