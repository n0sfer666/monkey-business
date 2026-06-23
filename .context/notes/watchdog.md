# Connectivity watchdog

Модуль `root/usr/share/monkey-business/watchdog.sh`, запускается cron'ом раз в минуту
(`* * * * * .../watchdog.sh`, регистрируется в `deploy-vm.sh` → `/etc/crontabs/root`).

## Зачем
При `kill_switch=1` firewall fail-closed: упавший Xray/сервер дропает весь форвардимый
LAN-трафик. Watchdog детектит провал VPN и делает `init.d stop` (flush.sh снимает kill-switch
→ LAN на direct), затем периодически пробует поднять VPN обратно. Так проблема подключения не
валит устройство целиком (требование пользователя после инцидента 2026-06-18).

## Критерий здоровья (важно!)
VPN здоров ⟺ **exit-IP через socks ≠ домашний (direct) IP**. Это буквальное «туннель несёт
трафик» и НЕ зависит от geoip, имени сервера или того, что цель пробы попала в direct-лист.
Пробит echo-IP сервисами (`PROBE_URLS`: ipify/ifconfig.me/icanhazip, первый отдавший IPv4),
которые маршрутизируются через proxy — их НЕЛЬЗЯ держать в direct-листе. `curl -4` для сравнимости.

> Регресс 2026-06-22: раньше критерием был `countryCode` == страна сервера, а проба била по
> `ip-api.com`, который у пользователя в direct-листе → уходила мимо туннеля → всегда домашний
> RU-IP → вечный fail → `init.d stop` каждые 5 мин → дашборд залипал в «Starting…».

## Машина состояний (стейт в tmpfs `/tmp/mb-watchdog/state`, лог `/usr/local/server.main.log`)
- `intent = global.enabled`. Если 0 — watchdog idle (стейт удаляется), VPN-жизненным циклом не рулит.
- **HEALTHY**: каждые 60с обновляет домашний IP (`direct_probe`) и пробит exit через socks5h
  `127.0.0.1:10808`. Успех = валидный exit-IP, отличный от домашнего; фиксируется в `WD_BASE_IP`.
  5 провалов подряд → `init.d stop` → проба direct → лог инцидента → **DOWN** (ретрай каждые 10 мин).
- **DOWN**: проба direct (LAN уже на direct, не трогаем). Сеть мертва → лог при переходе, ждём
  10 мин. Сеть ожила → лог + `init.d start` + до 5 быстрых проб VPN. Успех → HEALTHY; иначе
  `init.d stop` (назад на безопасный direct), лог, остаёмся DOWN.

## Свойства
- Флэш-бережно: стейт в tmpfs, лог ТОЛЬКО на переходах + ротация по `LOG_MAX`.
- Идемпотентно, flock от наложений, все `curl` с `--max-time`. Смена сервера (tag) сбрасывает exit-baseline.
- Env-override параметров (`MB_WD_*`) + хук `MB_WD_SOURCED=1` для юнит-теста машины состояний
  (`test/unit/watchdog_test.sh`, мок I/O, без сети/root, в `make test-unit`).

## TODO дистрибуции
ipk-путь (`scripts/package.sh`, ещё не реализован) должен ставить `watchdog.sh` + cron-строку
+ `cron enable` так же, как `deploy-vm.sh`.
