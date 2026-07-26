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

## Попутные баги (исправлены отдельной задачей)
1. **`apply.sh` меняет nft-таблицу неатомарно** — окно без kill-switch на каждом reload.
   → `2026-07-26-atomic-nft-swap.md`.
2. **`enabled` не является источником истины для рантайма** — `START=95` поднимал туннель на загрузке
   независимо от тумблера, `config_apply` включал VPN молча. → `2026-07-26-enabled-gate.md`.
