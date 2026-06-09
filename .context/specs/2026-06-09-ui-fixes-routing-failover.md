# Спека: UI-фиксы, маршрутизация, failover, трафик (2026-06-09)

## Контекст
6 проблем/фич из ручного тестирования живой VM. Базис: rpcd(ucode)+UCI+генератор→Xray, LuCI client-side JS.
Доп. найдено: `configApply` передаёт в генератор только `{global,server}` (dns/anti_dpi игнорируются);
нет geo .dat (xray не стартует с geoip/geosite); никто не выставляет `selected.server`.

## Требования

### R1 — Subscription fetch без предварительного save (#1)
- Кнопка «Fetch subscription» (servers) шлёт URL из ПОЛЯ формы (не из сохранённого UCI).
- Успех → сохранить URL в UCI + показать кол-во серверов + userinfo.
- «Save & Apply» (servers) → сохранить URL, скачать, провалидировать, обновить серверы.

### R2 — Turn on реально подключает (#2)
- `service_toggle(on)`: выбрать сервер (R4), сгенерировать конфиг (полный: global+server+dns+anti_dpi+custom),
  провалидировать (`xray -test`), записать, запустить init.d, enabled=1. off → stop, enabled=0.
- Конфиг невалиден / сервер недоступен → вернуть `error`, НЕ оставлять «вечный Starting».
- Dashboard: после toggle поллить status; running→Connected, ошибка→показать.

### R3 — Settings Save & Apply без «no server selected» (#3)
- `configApply` авто-выбирает сервер (R4), если не выбран.
- `configApply` передаёт в генератор dns + anti_dpi + custom-списки (XHTTP padding и пр. реально применяются).

### R4 — Приоритеты серверов + connect-time failover (#4)
- У `server` есть `priority` (uint, меньше = выше). Сортировка по priority.
- Выбор сервера: первый ДОСТУПНЫЙ по приоритету (tcpPing). Нет доступных → первый по приоритету (или error).
- UI: редактируемый priority в GridSection серверов.
- Runtime-failover НЕ требуется (решение пользователя) — только при connect/apply.

### R5 — Custom direct/vpn + geo (#5)
- Dashboard: 2 textarea (Direct, Via VPN). Каждая строка: domain | IP/CIDR | `geoip:xx` | `geosite:xx`.
- Применяются ТОЛЬКО в split-tunnel режимах (routing_mode != global). В global — игнор.
- Правила добавляются ПЕРЕД правилами режима: direct-список→`direct`, vpn-список→`proxy`.
- Geo .dat: `update-geo.sh` качает geoip.dat+geosite.dat (Loyalsoldier/v2ray-rules-dat latest) в
  `/usr/share/xray/`. Кнопка «Update geo» + авто при apply, если файлов нет. UI показывает статус geo.
- Категории geosite/geoip привести к набору Loyalsoldier (проверка реальным `xray -test`).

### R6 — Трафик подписки на дашборде (#6)
- `fetchSubscription` захватывает заголовок `Subscription-Userinfo: upload=..;download=..;total=..;expire=..`.
- Парсить → сохранить в UCI subscription (used_upload/used_download/total/expire). `status` отдаёт.
- Dashboard сверху: использовано/всего (GB) + % + дата истечения. Нет данных → не показывать.

## Архитектура / изменения
- **UCI**: `subscription`: +used_upload,used_download,total,expire. `global`: +custom_direct,custom_proxy.
  `server`: +priority.
- **handlers.uc** (host-tested): subscriptionUpdate(сохр.url+userinfo+автовыбор), configApply(полный конфиг+автовыбор),
  serviceToggle(connect/disconnect), status(+traffic), selectBest(priority+ping), helper parseUserinfo.
- **monkey-business.uc** (ctx): fetchSubscription→{body,userinfo}; applyConfig→валидация xray -test;
  selectServer setter; geoReady/updateGeo.
- **xray.uc**: buildRouting +custom direct/proxy (split-only); generate берёт anti_dpi+custom из config.
- **Frontend**: servers.js(R1,R4), dashboard.js(R2,R5,R6), settings.js(R3).
- **update-geo.sh** (new): скачивание dat.

## Edge cases
- Пустой URL в поле fetch → понятная ошибка.
- Userinfo заголовка нет → traffic не показываем.
- Все серверы недоступны → error при connect (не Starting).
- geo .dat нет при apply → авто-докачка; нет сети → понятная ошибка.
- custom-списки с мусором → пропускать строку, не падать.
- xray -test fail → error с первой строкой stderr.

## Риски
- Категории geo не совпадут с Loyalsoldier dat → xray не стартует. Митигация: валидация `xray -test` (T3) +
  integ-тест против реального xray; подгонять категории.
- Размер dat на 512MB-диске dev-VM. Митигация: ext4 resize 512M хватает (~10MB dat).

## Тестовая стратегия (T3+T4)
- **T4 (unit, host)**: parseUserinfo, selectBest(priority+ping mock), buildRouting с custom (split vs global),
  configApply передаёт dns/anti_dpi, subscriptionUpdate сохраняет url+userinfo+автовыбор. Расширить golden-снапшоты.
- **T3 (dev-VM + браузер)**: реальный fetch→servers, Turn on→Connected (xray реально стартует с geo),
  settings save&apply без ошибки, custom-правила в конфиге, traffic на дашборде. Скриншоты.
- Базово: shellcheck/ucode/js + `make test` зелёные перед каждым коммитом.

## DoD
- Все 6 пунктов воспроизводимо работают в браузере на dev-VM (Turn on → Connected, xray running).
- `make test` зелёный; новые unit покрывают R1–R6 логику.
