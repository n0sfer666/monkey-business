# Connectivity watchdog

Модуль `root/usr/share/monkey-business/watchdog.sh`, запускается cron'ом раз в минуту
(`* * * * * .../watchdog.sh`, регистрируется в `deploy-vm.sh` → `/etc/crontabs/root`).

## Зачем
При `kill_switch=1` firewall fail-closed: упавший Xray/сервер дропает весь форвардимый
LAN-трафик. Watchdog детектит провал VPN и делает `init.d stop` (flush.sh снимает kill-switch
→ LAN на direct), затем периодически пробует поднять VPN обратно. Так проблема подключения не
валит устройство целиком (требование пользователя после инцидента 2026-06-18).

## Машина состояний (стейт в tmpfs `/tmp/mb-watchdog/state`, лог `/usr/local/server.main.log`)
- `intent = global.enabled`. Если 0 — watchdog idle (стейт удаляется), VPN-жизненным циклом не рулит.
- **HEALTHY**: проба каждые 60с через socks5h `127.0.0.1:10808` на `ip-api.com/json`. Успех =
  `status:success` И `countryCode` == baseline ИЛИ == подсказке из имени сервера (`hint_cc`).
  Первый успех фиксирует baseline (cc+ip). 5 провалов подряд → `init.d stop` → проба direct →
  лог инцидента → **DOWN** (ретрай каждые 10 мин).
- **DOWN**: проба direct (LAN уже на direct, не трогаем). Сеть мертва → лог при переходе, ждём
  10 мин. Сеть ожила → лог + `init.d start` + до 5 быстрых проб VPN. Успех → HEALTHY; иначе
  `init.d stop` (назад на безопасный direct), лог, остаёмся DOWN.

## Свойства
- Флэш-бережно: стейт в tmpfs, лог ТОЛЬКО на переходах + ротация по `LOG_MAX`.
- Идемпотентно, flock от наложений, все `curl` с `--max-time`. Смена сервера (tag) сбрасывает baseline.
- Env-override параметров (`MB_WD_*`) + хук `MB_WD_SOURCED=1` для юнит-теста машины состояний
  (`test/unit/watchdog_test.sh`, мок I/O, без сети/root, в `make test-unit`).

## TODO дистрибуции
ipk-путь (`scripts/package.sh`, ещё не реализован) должен ставить `watchdog.sh` + cron-строку
+ `cron enable` так же, как `deploy-vm.sh`.
