# 2026-07-26 — Apply должен доезжать до xray (reload через rc_procd)

## Контекст
Пользователь добавил `chatgpt.com` в список «Via VPN» на дашборде, UI ответил «Routing rules
applied», но сайт продолжал видеть настоящий IP. Список и генератор были ни при чём: `chatgpt.com`
лёг в `monkey-business.global.custom_proxy`, попал в `routing.rules` → `outboundTag: "proxy"`, файл
`/etc/monkey-business/xray.json` перезаписался и прошёл `xray run -test`. Не сработал последний шаг:
процесс xray жил с прошлой загрузки и держал в памяти конфиг без нового правила.

`applyConfig` (rpcd) звал `/etc/init.d/monkey-business reload`, рассчитывая, что procd переобъявит
инстанс, увидит новый хеш `procd_set_param file $CONF` и перезапустит только xray — без
`stop_service`, чтобы `flush.sh` не снял kill-switch. Но в `/etc/rc.common` (OpenWrt 25.12.1) блок
`USE_PROCD` переопределяет `reload()` как `procd_lock; reload_service "$@"` — БЕЗ
`procd_open_service`/`procd_close_service`. Ubus-вызов `set` делает только `procd_close_service`,
поэтому голый `start_service` не отправлял procd ничего: xray не трогался, а видимый эффект был лишь
от побочки — `apply.sh` внутри `start_service` переприменял firewall («tproxy firewall applied» в
логах есть, перезапуска нет).

Масштаб: молча ломались ВСЕ применения конфига из UI — правки списков, настройки, смена сервера,
включение тумблером (xray оставался мёртвым). Failover watchdog'а тоже: `try_failover` писал новый
конфиг и новый тег в `active`, а xray продолжал держать старый сервер. Маскировалось тем, что
`vpn_reconnect` убивает xray руками и procd поднимает его уже с новым файлом — изменения «доезжали»
с задержкой до минуты или после перезагрузки.

## Решение
```sh
reload_service() {
	[ -f "$CONF" ] || return 1
	rc_procd start_service
}
```
- `rc_procd` (обёртка из rc.common) открывает и закрывает procd-сервис вокруг `start_service`, т.е.
  переобъявление реально уходит в ubus с `method=set`. Инстансы с неизменившимся хешем при этом
  живут — байт-в-байт тот же конфиг не даёт лишнего рестарта.
- Аргументы не передаём намеренно: `rc_procd` смотрит `[ -n "$2" ]` и любой лишний аргумент
  переключил бы `set` на `add`, а `add` не вычищает отсутствующие инстансы.
- Guard на `$CONF` обязателен: `procd_close_service` шлёт `set` безусловно, поэтому при отсутствующем
  конфиге ушёл бы `set` с пустыми `instances{}` — procd снёс бы инстанс и убил ЖИВОЙ xray, причём
  `stop_service`/`flush.sh` не вызывается, и kill-switch остался бы поднят: LAN заперт без туннеля.
  Воспроизведено на железе (pid исчезал, `instances=0`), самолечение только через watchdog (~3 мин).
- `restart_service` заводить нельзя: он позвал бы `stop_service` → `flush.sh`, а это окно, в котором
  kill-switch снят, а xray ещё не поднялся.
- `service_triggers` с `procd_add_reload_trigger` снят: `$CONF` генерит rpcd и сам зовёт `reload`, а
  триггер поднимал бы xray на любом `uci commit` через LuCI — в том числе когда пользователь
  выключил VPN. Единственными потребителями триггера были `uci.apply()` из `settings.js` и
  `servers.js`, и оба применяют конфиг явно (`servers.js` — только при `st.running`).

Регрессионный тест: `test/unit/initd_test.sh` — сорсит init-скрипт с моками procd/uci/logger/sh и
требует переобъявления инстанса (`open_service` → `param file $CONF` → `close_service set`),
отсутствия `flush.sh` на reload и отсутствия `set` при пропавшем конфиге. Без фикса падает.

## Попутные баги (НЕ исправлены, требуют отдельной задачи)
1. **`apply.sh` меняет nft-таблицу неатомарно** — `nft delete table inet monkey_business`, затем
   отдельным процессом `nft -f -` создаёт заново. Между вызовами нет ни kill-switch, ни tproxy, и
   форвард LAN→WAN уходит открытым через fw4. Окно открывается на каждом `reload`, т.е. в фазе `down`
   watchdog'а — 144 раза в сутки. Лечится одним документом `nft -f` (`table` / `delete table` /
   `table { … }` в одной транзакции). Задеть может boot-старт, `flush.sh`, `vpn_start`/`tick_down` и
   netns-харнесс, который парсит вывод nft.
2. **`enabled` не является источником истины для рантайма.** Init-скрипт его вообще не читает:
   `START=95` поднимает xray на загрузке независимо от тумблера, а `settings.js` зовёт `config_apply`
   безусловно — сохранение настроек при выключенном VPN поднимает туннель, пока дашборд показывает
   «off», и watchdog при `read_intent=0` никого не сторожит. До этого фикса тот же путь давал другой
   плохой исход (kill-switch без xray, LAN мёртв). Чинить надо гейтом по `enabled`, но сперва
   переставить `setEnabled(true)` ПЕРЕД `applyConfig` в `serviceToggle` (`src/rpcd/handlers.uc`),
   иначе гейт сломает первое включение.
