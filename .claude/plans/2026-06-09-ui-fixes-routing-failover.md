# План: UI-фиксы, маршрутизация, failover, трафик (2026-06-09)

Спека: `.context/specs/2026-06-09-ui-fixes-routing-failover.md`. Решения: failover=connect-time,
geo=download(Loyalsoldier), custom routing=split-only, проверка=T3+T4.

## Задачи (по зависимостям)

### T1 — UCI-схема (R1,R4,R5,R6)
- `root/etc/config/monkey-business`: subscription +used_upload/used_download/total/expire;
  global +custom_direct/custom_proxy; server-секции priority (дефолтных нет — добавятся при fetch).
- Проверка: T1 (ucode syntax/lint).

### T2 — handlers.uc + unit (R1,R2,R3,R4,R6) [ядро]
- `parseUserinfo(str)` → {used_upload,used_download,total,expire}.
- `selectBest(ctx)` → первый доступный по priority (ctx.pingServer), фиксирует selected; нет живых→первый.
- `subscriptionUpdate`: использовать args.url; при успехе ctx.setSubscriptionUrl + setUserinfo + авт`selectBest`.
- `configApply`: автовыбор если нет; generate({global,server,dns,anti_dpi,custom_direct,custom_proxy}).
- `serviceToggle(on)`: on→selectBest+applyConfig(возврат error при невалидном)+setEnabled(1)+start; off→stop+enabled0.
- `status`: +traffic (из subscription), +selected priority.
- `test/unit/rpcd_test.uc`: расширить (parseUserinfo, selectBest, configApply передаёт dns/anti_dpi,
  serviceToggle connect-флоу, subscriptionUpdate сохр.url+userinfo+select). **T4**.

### T3 — xray.uc + snapshots (R3,R5)
- `generate`: брать `config.anti_dpi`, `config.custom_direct`, `config.custom_proxy`.
- `buildRouting`: парсить custom-списки (domain/ip/geoip:/geosite:), добавлять ПЕРЕД mode-rules
  (direct→direct, proxy→proxy) только при mode!=global.
- Категории под Loyalsoldier (geoip:ru, geosite:category-ru/private; gfwlist подогнать).
- `test/unit/generator_test.uc`: снапшоты с custom (split) и без (global). **T4**.

### T4 — ctx рантайм (R1,R2,R5,R6)
- `root/usr/share/rpcd/ucode/monkey-business.uc`: fetchSubscription→{body,userinfo} (uclient-fetch -S, парс заголовка);
  setSubscriptionUrl/setUserinfo; selectServer(tag) setter; applyConfig валидирует `xray -test -c` (error→строка stderr);
  geoReady()/updateGeo() через update-geo.sh; новые ubus-методы: geo_update(есть), set_custom (или через config_apply).

### T5 — update-geo.sh (R5)
- `root/usr/share/monkey-business/update-geo.sh`: качать geoip.dat+geosite.dat (Loyalsoldier latest) в
  `/usr/share/xray/` (uclient-fetch), атомарно, понятные коды. Deploy кладёт + chmod.
- `deploy-vm.sh`: добавить файл в раскладку.

### T6 — servers.js (R1,R4)
- Fetch button: читать live-значение url (`this.section.formvalue`/map), передавать в subscription_update; успех→сохранять.
- handleSaveApply: save url → fetch → validate.
- priority-колонка (form.Value uint) в GridSection; сорт по priority.

### T7 — settings.js (R3)
- Убедиться, что Save&Apply теперь без «no server» (логика в T2). При необходимости — показать выбранный сервер.

### T8 — dashboard.js (R2,R5,R6)
- Turn on: toggle→poll status N сек→Connected/ошибка (показать xray error).
- Traffic-блок сверху (used/total GB, %, expire) из status.
- 2 textarea (Direct/Via VPN) → global.custom_direct/custom_proxy + кнопка Save&Apply.
- Кнопка «Update geo databases» + статус.

### T9 — ACL/menu
- `luci/root/usr/share/rpcd/acl.d/...`: разрешить все ubus-методы monkey-business (read+write).

### T10 — Деплой + T3-верификация (DoD)
- `make dev-deploy`; в браузере (Claude-in-Chrome) пройти все 6 сценариев, xray реально RUNNING, скриншоты.
- Чинить до зелёного. `make test` зелёный.

## Definition of Done
- 6 пунктов воспроизводимо работают в браузере на dev-VM; Turn on→Connected (xray running с geo).
- Настройки (XHTTP padding, dns, custom) реально в xray.json. Трафик виден. Приоритеты/выбор работают.
- `make test` зелёный; unit покрывают R1–R6.

## Проверки (команды)
- Базово каждый таск: `make test` (lint shellcheck/ucode/js + 43→N unit).
- T3: `make dev-deploy` + браузерные сценарии + `ubus call`/`xray -test` в VM.
- `.claude/.verify-state.json` перед каждым коммитом.

## Коммиты (conventional, autocommit per custom-flow)
- по таскам: fix(servers)/feat(routing)/feat(dashboard)/fix(rpcd)/feat(geo) и т.д.
