# Spec: direct-bypass + opensource-дефолты + geofiles при установке

**Дата:** 2026-06-30
**Статус:** РЕАЛИЗОВАНО и проверено на QEMU (B/C/D). На железо деплоит юзер сам.
**Контекст сессии:** диагностика «direct тормозит» + «вижу 5 серверов вместо 7» + скролл серверов.

## Результат проверки (QEMU, 2026-06-30)

- **B** — `direct_dns` дефолт `77.88.8.8` в 4 местах (config/settings.js/xray.uc×2); live-uci VM = `77.88.8.8`.
- **C** — деплой скачал geoip.dat 18.4MB + geosite.dat 10.3MB (`geo status` ok), собрал ru-сет. Идемпотентно.
- **D** — `ruset.sh build`: v4=12958 v6=11977 (точные числа Loyalsoldier). nft-таблица с bypass-сетами
  грузится; auto-merge схлопнул в 7632 v4-интервала. **Interval-membership: 77.88.8.8 (RU) ∈ mb_ru4
  → return/accept; 8.8.8.8 (US) ∉ → tproxy→xray.** `apply.sh` BYPASS=1 даёт сеты+return(до tproxy)+
  accept(до drop); BYPASS=0 — ruleset байт-в-байт как был (грейсфул). Идемпотентность ru-сета (sha256).
- **Регрессия:** `test/unit/firewall_test.sh` (12) + `test/unit/ruset_test.sh` (14). lint+весь suite зелёные.
- **Граница проверки:** полный packet-level kill-switch leak-test (реальный tproxy+xray) в QEMU невозможен —
  офлайн-песочница без `kmod-nft-tproxy`/`xray-core`. Логика kill-switch проверена на уровне nft-ruleset
  (membership + порядок правил). Финальный T4 packet-тест — при деплое юзера на R2S.

## Цель (opensource UX)

После установки пользователю нужно только: добавить подписку + выставить приоритет серверов.
Всё остальное (geofiles, быстрый direct DNS, direct-bypass) — из коробки.

## Фон / находки диагностики

- **«5 vs 7» — ИСПРАВЛЕНО и ПОДТВЕРЖДЕНО на железе (=7).** Реальная структура подписки VPNON
  (снято с устройства, uuid замаскирован), все поля кроме адреса и tag одинаковы
  (sni=fortwine.ru, pbk/sid общие, xhttp/stream-one, fp=edge):
  - 🚀 RU `ru.vpnon-connect.tech:10443`, 🚀 NL `tds.*:10444`, 🚀 FR `tds.*:10445`, 🚀 EE `tds.*:10446`
    — 4 РАЗНЫХ эндпоинта (различаются host:port).
  - 🛡️ NL / 🛡️ FR / 🛡️ EE — все три = `hop.vpnon-connect.tech:10444`, **байт-в-байт идентичны**,
    различаются ТОЛЬКО tag (флаг страны косметический; это один и тот же сервер).
  Прежний `serverKey` (`address:port:uuid:transport`) схлопывал 3 🛡️ в 1 → виделось 5.
  **Фикс:** `serverKey` = `tag` + полная идентичность подключения
  (`tag|address|port|uuid|security|flow|sni|fingerprint|alpn|pbk|sid|spx|transport.*`). 4 🚀
  раздельны по адресу, 3 🛡️ — по tag → 7 видно; схлоп только при совпадении ВСЕГО (истинный дубль).
  **Нюанс:** 3 🛡️ = один endpoint, failover между ними бесполезен; их флаги стран чисто
  косметические. **Trade-off:** tag в ключе → ручной ренейм сервера подписки ломает
  order-preservation на re-fetch (drag-сортировка не затронута). Регрессия `test/unit/rpcd_test.uc`
  + `test/fixtures/sub_hop_dupes.txt`. Теги/флаги из `#fragment` (`subscription.uc:62-63`).
  **Грабли деплоя:** stale detached rpcd (от ubus-wedge-recovery в deploy-vm.sh) держал старый
  ucode → после заливки хендлера нужен `killall rpcd` + рестарт, иначе ubus отвечает старым кодом.
- **Корень «direct тормозит» = отсутствие geo-баз.** Без `/usr/share/xray/{geoip,geosite}.dat`
  правила `geoip:ru`/`geosite:category-ru` не матчат → RU-трафик уходит в proxy = медленно.
  Отсюда же «без ручного update geofiles половина не работает». На железе юзера базы есть
  (18MB/10MB), поэтому direct там был быстрым (ya.ru 42ms).
- Внутри xray direct-путь уже почти оптимален: `sniffing.routeOnly:true` (tproxy-in,
  `xray.uc:28`) + freedom-outbound без domainStrategy (=AsIs, оригинальный IP).
- `direct_dns` дефолт `223.5.5.5` (AliDNS, Китай) — медленно/нестабильно для RU.

## Объём работ

### A. Скролл «Manual servers» — ✅ УЖЕ СДЕЛАНО и проверено в браузере
`luci/htdocs/luci-static/resources/view/monkey-business/servers.js` — после `m.render()`
оборачивает `table.cbi-section-table` в `div.mb-scroll {max-height:55vh;overflow-y:auto}`,
sticky-шапка через `<style>`, MutationObserver переоборачивает таблицу после ре-рендера
GridSection (Add/Delete/Save). Проверено вживую: скролл + sticky + переживание ре-рендера.
Едет вместе с остальным.

### B. Yandex `77.88.8.8` дефолтом (T1)
Заменить `223.5.5.5` → `77.88.8.8` в 4 местах:
- `root/etc/config/monkey-business:23` — `option direct_dns`
- `luci/htdocs/luci-static/resources/view/monkey-business/settings.js:59` — `direct.default`
- `src/generator/xray.uc:56` — fallback dns-инбаунда `dns.direct_dns || "..."`
- `src/generator/xray.uc:119` — fallback split-DNS `dns.direct_dns || "..."`
Отдельно: обновить live-uci на железе юзера (его текущее значение 223.5.5.5) — делает юзер/я
вручную, не часть деплоя.

### C. Geofiles при установке (T3 на QEMU)
В `scripts/deploy-vm.sh`, REMOTE-блок, ПОСЛЕ установки пакетов (после строки ~148, до
рестарта rpcd), идемпотентно и НЕ фатально:
```sh
if command -v xray >/dev/null 2>&1; then
  if [ ! -s /usr/share/xray/geoip.dat ] || [ ! -s /usr/share/xray/geosite.dat ]; then
    echo ">> downloading geo databases…"
    sh /usr/share/monkey-business/geo.sh download || echo "   (geo download failed — update later in UI)"
  fi
  sh /usr/share/monkey-business/ruset.sh build || true   # см. D
fi
```
`geo.sh download` уже идемпотентен (sha256-skip), валидирует через xray. Покрывает и
`make deploy`, и прямой `deploy-vm.sh` (deploy.sh → deploy-vm.sh).

### D. nft direct-bypass (critical, T4)
RU/private трафик НЕ заходит в xray — нативная маршрутизация ядром (макс. скорость на A53).

**D1. Новый `root/usr/share/monkey-business/ruset.sh`** (по образцу `geo.sh`, отдельная
ответственность):
- Источник RU-CIDR: `https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text/ru.txt`
  (та же экосистема, что geoip.dat → консистентно с `geoip:ru` xray). ~13k v4 + ~12k v6 CIDR.
  Override: `uci get monkey-business.geo.ru_set_url`.
- Команды: `build` (скачать, провалидировать формат CIDR, сгенерить nft-element-файлы,
  идемпотентно по sha256), `status` (JSON: present/count/state).
- Выход: `/usr/share/monkey-business/ru4.nft` и `ru6.nft` вида
  `add element inet monkey_business mb_ru4 { 2.16.20.0/23, ... }` (разбить v4/v6 по наличию `:`).
  Декаплинг: набор грузится отдельно от создания таблицы → refresh без полного reapply
  (`nft flush set inet monkey_business mb_ru4; nft -f ru4.nft`).
- State-файл `/tmp/mb-ruset.state`. Размер файла скрипта ≤200 строк.

**D2. `scripts/firewall/apply.sh`** (правка):
- Новый env: `BYPASS="${MB_DIRECT_BYPASS:-1}"`.
- В таблице `inet monkey_business` объявить (только при `BYPASS=1`):
  ```
  set mb_ru4 { type ipv4_addr; flags interval; auto-merge; }
  set mb_ru6 { type ipv6_addr; flags interval; auto-merge; }
  ```
- В `chain prerouting`, ПОСЛЕ private-return, ДО tproxy-строки (line 53):
  ```
  iifname "$LAN" ip  daddr @mb_ru4 return
  iifname "$LAN" ip6 daddr @mb_ru6 return
  ```
- В `chain forward` (kill-switch), ПЕРЕД `drop` (после private-accept):
  ```
  iifname "$LAN" ip  daddr @mb_ru4 accept
  iifname "$LAN" ip6 daddr @mb_ru6 accept
  ```
- После успешного `nft -f -` создания таблицы — подгрузить элементы (guarded):
  ```
  [ "$BYPASS" = 1 ] && { [ -f .../ru4.nft ] && nft -f .../ru4.nft; [ -f .../ru6.nft ] && nft -f .../ru6.nft; } || true
  ```
- При `BYPASS=0` или пустых сетах — поведение как сегодня (RU через xray). Грейсфул.

**D3. `root/etc/init.d/monkey-business:25-27`** — прокинуть env в apply.sh:
```sh
MB_DIRECT_BYPASS="$(uci -q get monkey-business.global.direct_bypass || echo 1)" \
```
рядом с существующими `MB_LAN_IFACE`/`MB_KILL_SWITCH`.

**D4. `root/etc/config/monkey-business`** — добавить:
- в `global`: `option direct_bypass '1'`
- в `geo`: `option ru_set_url ''`

**D5. `scripts/deploy-vm.sh`** — добавить `ruset.sh` в staging (cpf + chmod 755 рядом с geo.sh,
строки 61-62) и в chown/chmod-списки REMOTE-блока. Вызов `ruset.sh build` — см. C.

**D6. Refresh-цикл** — ru-set обновлять вместе с geofiles (install + при ручном/cron update
geofiles). После build → reload set + (если набор изменился) гарантировать, что apply.sh уже
применён. Минимально: `ruset.sh build` на деплое; кнопку/cron можно добавить позже.

**D7. xray-генератор НЕ трогаем** — правило `geoip:ru→direct` остаётся safety-net для RU-IP,
не попавших в nft-сет (тогда просто медленнее через xray, не утечка).

**D8. (опц.) LuCI** — тумблер `direct_bypass` на Settings (`settings.js`). Можно отложить.

## Анализ kill-switch (почему безопасно)

Порядок prerouting: `private return → @mb_ru4/6 return → dport53 return(→dnat) → else tproxy`.
Forward (fail-closed): `accept private → accept @mb_ru4/6 → drop`.
- **VPN down (xray упал):** proxy-трафик не терминируется tproxy → попадает в forward → НЕ
  private, НЕ RU → `drop` (утечки нет). private и RU → `accept` → идут нативно (как и должны).
- **Пустой/недокачанный сет:** RU-IP не матчится → идёт в tproxy → xray → direct (медленнее,
  но безопасно). Грейсфул-деградация.
- **Над-включение** (non-RU IP ошибочно в сете → пойдёт direct мимо proxy): минимизировано
  выбором Loyalsoldier-источника (RU-allocated, консервативно). Это privacy-риск, НЕ leak.

## DoD

1. Свежая установка на QEMU: после деплоя без ручных действий — geofiles на месте,
   `direct_dns=77.88.8.8`, сеты `mb_ru4/6` наполнены, bypass активен. Остаётся только
   подписка + приоритет.
2. RU-трафик не идёт через xray: counter на bypass-return растёт при curl RU; CPU xray не
   реагирует на RU-нагрузку.
3. Kill-switch без утечки (T4): остановить xray → curl RU-сайт = ОК, curl proxy-сайт = блок.
4. Скролл серверов работает (уже проверено).

## Проверка (ТОЛЬКО QEMU, на железо НЕ деплоить — это делает юзер сам)

- `make dev-up` → `make dev-provision` → `make dev-deploy` (deploy-vm.sh на VM:2222,
  HTTP:8090). Подписку добавить через uci/UI (URL у юзера, в репо НЕ хранить — секрет).
- Проверки: `nft list set inet monkey_business mb_ru4 | head`; `nft list chain inet
  monkey_business prerouting` (counters); geo `sh geo.sh status`; `uci get
  monkey-business.dns.direct_dns`.
- Kill-switch leak-test: `/etc/init.d/monkey-business stop` xray (или `killall xray`) →
  с LAN-клиента VM проверить RU vs proxy. Расширить `test/` (есть `dev-test-split`,
  `test/unit/deploy_test.sh`) регрессией split+bypass+kill-switch.

## Out of scope / заметки

- НЕ деплоить на железо (R2S 192.168.1.1) — только QEMU; финальный деплой делает юзер.
- Ссылка на подписку — СЕКРЕТ, не в репо/спеку (доступна в uci на устройстве).
- Память `mb-direct-is-xray-only` УСТАРЕВАЕТ после D (появляется nft direct-set). Обновить.
- Файлы кода ≤200 строк (apply.sh сейчас 65, ruset.sh новый — следить за лимитом).
