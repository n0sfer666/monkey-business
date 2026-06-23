# Connectivity watchdog

Модуль `root/usr/share/monkey-business/watchdog.sh` (+ `probes.sh` — слой сетевых проб),
запускается cron'ом раз в минуту (`* * * * * .../watchdog.sh`, регистрируется в `deploy-vm.sh`
→ `/etc/crontabs/root`). `watchdog.sh` сорсит `probes.sh` по `MB_WD_LIB` (дефолт — каталог скрипта,
фолбэк `/usr/share/monkey-business`).

## Зачем
При `kill_switch=1` firewall fail-closed: упавший Xray/сервер дропает весь форвардимый
LAN-трафик. Watchdog детектит провал и **сначала переподключает xray (reconnect)**, и только если
не помогло — `init.d stop` (flush.sh снимает kill-switch → LAN на direct), затем периодически
пробует поднять VPN. Так проблема подключения не валит устройство целиком (требование пользователя
после инцидентов 2026-06-18 / 2026-06-23).

## Сигналы здоровья (важно!)
Две раздельные пробы (`probes.sh`):
- **liveness** (часто, дёшево, небанируемо): `live_probe` — TLS-handshake через socks к
  иностранному IP (`LIVE_URLS`: 1.1.1.1, 8.8.8.8). Успех = xray несёт трафик в туннель. НЕ зависит
  от echo-сервиса, нет тела/rate-limit. Цели обязаны быть **proxied** (foreign, НЕ в direct-листе).
- **exit-IP** (редко, раз в `EXIT_EVERY` циклов, либо force в reconnect/recovery): exit через socks
  ≠ домашний (direct) IP — ловит утечку трафика мимо туннеля. Бьёт echo-IP (`PROBE_URLS`:
  ipify/ifconfig.me/icanhazip, первый IPv4), `curl -4`. Эти хосты тоже НЕЛЬЗЯ держать в direct.

`health_check(force)` = liveness обязателен; exit-сверка при `force=1` или подошёл `EXIT_EVERY`-цикл.

> Регресс 2026-06-22: критерием был `countryCode`, проба била по `ip-api.com` (в direct-листе) →
> мимо туннеля → вечный fail → `init.d stop` каждые 5 мин.
> Редизайн 2026-06-23: одиночная echo-проба каждые 60с давала ложные «туннель упал» (rate-limit
> общего exit-IP, отказ echo-сервиса) → лишний снос на direct. Лечилось ручным reconnect — теперь
> reconnect делает сам watchdog. См. `.context/specs/2026-06-23-watchdog-reconnect-strategy.md`.

## Машина состояний (стейт в tmpfs `/tmp/mb-watchdog/state`, лог `/usr/local/server.main.log`)
`intent = global.enabled`. Если 0 — watchdog idle (стейт удаляется). Фазы `healthy → reconnecting
→ down` (+ обратно). Смена сервера (tag) сбрасывает exit-baseline и счётчики.

- **HEALTHY** (каждые `POLL`=60с): cold-start xray если мёртв; `health_check`. Успех → fails=0.
  `FAIL_LIMIT`=3 фейла подряд → если direct мёртв: `init.d stop` → **DOWN(net)** (локальный
  интернет, reconnect бессмыслен); если direct жив: → **RECONNECTING**.
- **RECONNECTING** (каждые `POLL`): direct умер → DOWN(net). Иначе `vpn_reconnect` (bounce xray,
  kill-switch держится) + до `REC_TRIES`=3 быстрых `health_check 1`. Помогло → HEALTHY. Не помогло
  → `RECONNECT_LIMIT`=2 попыток (по одной за tick) → `init.d stop` → **DOWN(vpn)**, LAN на direct.
- **DOWN** (каждые `BACKOFF`=600с): direct мёртв → ждём (net). Ожил → `init.d start` + до
  `RECOVERY_TRIES`=5 проб → HEALTHY либо назад `init.d stop`/DOWN(vpn).

Тайминг реального обрыва туннеля (direct жив): ~3 мин до reconnect-тира → ~2 мин reconnect →
direct. Одиночный блип liveness с HEALTHY не двигает.

## Reconnect без снятия kill-switch (ключевое)
`init.d stop`/`restart` зовёт `flush.sh` → удаляет nft-таблицу = **снимает kill-switch**. Поэтому
reconnect = `kill xray`: procd (`respawn` в init-скрипте) поднимает процесс заново, firewall не
трогается. Фолбэк `vpn_start`, если procd не поднял (порог respawn исчерпан).

## Параметры (env-override `MB_WD_*`, дефолты боевые)
`FAIL_LIMIT(3)` `RECONNECT_LIMIT(2)` `POLL(60)` `BACKOFF(600)` `EXIT_EVERY(5)` `REC_TRIES(3)`
`RECOVERY_TRIES(5)` `RECONNECT_WAIT(5)` `TIMEOUT(10)` `LIVE_TIMEOUT(6)` `REC_TIMEOUT(6)`
`LOG_MAX(65536)`. Плюс `MB_WD_NOW`(epoch), `MB_WD_LIB`, `MB_WD_SOCKS/LIVE_URLS/PROBE_URLS`.

## Свойства
- Флэш-бережно: стейт в tmpfs, лог ТОЛЬКО на переходах + ротация по `LOG_MAX`.
- Идемпотентно, flock от наложений, все `curl` с `--max-time`.
- Хук `MB_WD_SOURCED=1` для юнит-теста машины состояний (`test/unit/watchdog_test.sh`: моки
  live/vpn/direct/reconnect, `MB_WD_EXIT_EVERY=1` для детерминизма, без сети/root, в `make test-unit`).
- Оба файла ≤ 200 строк (правило проекта): probes.sh — пробы, watchdog.sh — машина состояний.

## TODO дистрибуции
ipk-путь (`scripts/package.sh`, ещё не реализован) должен ставить `watchdog.sh` + `probes.sh` +
cron-строку + `cron enable` так же, как `deploy-vm.sh`.
