# План: monkey-business (custom-flow)

Спека: `.context/specs/2026-06-05-monkey-business-vpn-client.md`

## Принципы исполнения

- Последовательно, каждый шаг → проверка → автокоммит (план = разрешение).
- Каждый шаг, кроме T1 (dev-среда), покрыт тестами.
- Шаг, меняющий поведение предыдущего, ревизует его тесты (секция «Ревизовать тесты»).
- Backend = ucode; unit/netns-тесты в Linux-контейнере (macOS host); цели в Makefile.
- Blocked-шаги (железо/секрет/живая VM): готовлю скрипты+инструкции, помечаю blocked, иду дальше.

## Стек и инструменты

- **Backend**: ucode (`.uc`) — парсер, генератор, rpcd-хендлеры.
- **UI**: LuCI client-side JS (luci-base, ubus/rpcd).
- **Конфиг**: UCI `/etc/config/monkey-business` → генератор → Xray JSON.
- **Перехват**: nftables TPROXY (fw4 include).
- **Тесты**: ucode-харнесс (unit/snapshot) + bash netns-харнесс (integ).
- **Сборка/прогон**: `Makefile` (+ `Dockerfile.test` Linux-контейнер), OpenWrt SDK для ipk.
- **Lint**: `ucode -c`, `shellcheck`, eslint.

## Проверки (checks.json)

```json
{"lint": "make lint", "types": "make check", "test": "make test-unit"}
```

- `make check` — `ucode -c` по всем `.uc` (синтаксис вместо типов).
- `make lint` — shellcheck + ucode -c + eslint.
- `make test-unit` — ucode unit/snapshot в контейнере.
- `make test-integ` — netns-харнесс в привилегированном контейнере.
- `make package` — сборка ipk через SDK (blocked без SDK — даём инструкцию).

---

## Задачи

### T0 — Репо + bootstrap `.context/` + скелет (Stage 1, без авто-тестов)

- `git init`, рабочая ветка `dev`.
- `.context/`: README, stack, architecture, conventions, testing, commits, checks.md, checks.json, env.md.
- Скелет: `src/{parser,generator,rpcd}/`, `luci/`, `test/{unit,integ,fixtures}/`, `scripts/`, `Makefile`, `Dockerfile.test`, `.gitignore`, `README.md`.
- ucode test-харнесс `test/harness.uc` (assert, runner).
- **Файлы**: см. выше.
- **Проверка**: T1 — `make lint` чисто на скелете; `make test-unit` запускается (0 тестов = ok); тест-контейнер собирается.
- **Тесты добавить**: харнесс (самопроверка одним sanity-тестом).
- **Ревизовать**: —
- **DoD**: репо инициализировано, `.context/` полный, `make lint && make test-unit` зелёные, коммит.

### T1 — Dev-среда QEMU aarch64 ImmortalWrt (Stage 1, exempt от тестов)

- `scripts/dev-vm.sh`: скачать ImmortalWrt aarch64 (QEMU/virt) образ, `dev-up`/`dev-ssh`/`dev-down`.
- Makefile-цели `dev-up`, `dev-ssh`.
- Док в `.context/notes/dev-env.md`.
- **Проверка**: T2 смоук — попытка boot в QEMU + SSH + LuCI доступен. Если автономно тяжело/недоступно → **blocked** с точными командами для тебя.
- **Тесты добавить**: — (exempt, смоук-скрипт `scripts/dev-smoke.sh`).
- **DoD**: скрипты готовы; boot подтверждён ИЛИ помечен blocked; коммит.

### T2 — Парсер подписки (ucode) (Stage 2 backend) [T4]

- `src/parser/subscription.uc`: auto-detect (base64-список `vless://` / clash-yaml stub / json), нормализация в server-объект (proto, addr, port, uuid, sni, pbk, sid, flow, transport=xhttp, name).
- Устойчивость к мусору/пустому/частичному.
- **Проверка**: T4 — unit на happy/malformed/empty/boundary; синтетические фикстуры (НЕ реальный секрет).
- **Тесты добавить**: `test/unit/parser_*.uc`, `test/fixtures/sub_*`.
- **Ревизовать**: —
- **DoD**: парсер возвращает нормализованный список; тесты зелёные; коммит.

### T3 — UCI-схема + генератор UCI→Xray JSON (ucode) (Stage 2 backend) [T4]

- UCI-схема `/etc/config/monkey-business` (global/subscription/server/routing/dns/anti_dpi).
- `src/generator/xray.uc`: вход — структура (как из UCI) → Xray JSON: inbound TPROXY (TCP+UDP), outbound VLESS+Reality+XHTTP, routing (bypass RU/CN geoip+geosite, private direct, default proxy), заглушки dns/anti-dpi (раскрываются в T9).
- **Проверка**: T4 — golden/snapshot JSON; валидность структуры.
- **Тесты добавить**: `test/unit/generator_*.uc`, `test/fixtures/xray_*.json`.
- **Ревизовать**: тесты T2 (контракт server-объекта — вход генератора).
- **DoD**: генерится валидный Xray-конфиг для bypass-RU; snapshot-тесты зелёные; коммит.

### T4 — rpcd-сервис (ubus-методы) на мок-данных (Stage 2) [T4]

- `src/rpcd/monkey-business.uc`: `status`, `servers.list`, `servers.ping` (mock), `subscription.update` (mock-источник), `geo.update` (stub), `config.apply` (dry-run генератор), `service.toggle` (mock).
- Источник мока — синтетическая фикстура (реальный захват = T6 blocked).
- **Проверка**: T4 — unit на хендлеры напрямую (без живого ubus).
- **Тесты добавить**: `test/unit/rpcd_*.uc`.
- **Ревизовать**: тесты T3 (config.apply вызывает генератор).
- **DoD**: методы возвращают корректные структуры на мок-входе; тесты зелёные; коммит.

### T5 — LuCI JS-приложение (подвязано к моку) (Stage 2) [T2/blocked-visual]

- `luci/`: dashboard (статус+тумблер+серверы+ping), серверы (подписка+ручной), настройки (единый экран, advanced-секции, tooltips RU/EN), первый запуск.
- Подвязка к rpcd (мок).
- i18n RU primary + EN.
- **Проверка**: T2 — eslint + загрузка LuCI в QEMU-VM + скриншот (likely **blocked**: нужна живая VM) → чек-лист ручной проверки.
- **Тесты добавить**: eslint-конфиг; smoke-проверка рендера (если харнесс позволит).
- **Ревизовать**: контракты rpcd (T4) — поля, которые читает UI.
- **DoD**: UI рендерит экраны на моке (в VM или по чек-листу); eslint чисто; коммит.

### T6 — Захват реального ответа VPNON для мока (Stage 2 финал) [BLOCKED-секрет]

- Скрипт `scripts/capture-sub.sh`: разовый fetch подписки, санитизация секретов, сохранение фикстуры.
- **BLOCKED**: нужна секретная ссылка + сетевой запрос к внешнему сервису → выполняется только по твоему явному триггеру (этап 3).
- **DoD**: скрипт+инструкция готовы; помечено blocked.

### T7 — TPROXY/nftables firewall (Stage 3) [T3 netns]

- `scripts/firewall/nft-tproxy.sh` + fw4-include; mark/правила TCP+UDP.
- **Проверка**: T3 — netns-харнесс: routing (RU direct / зарубеж VPN через fake-geo).
- **Тесты добавить**: `test/integ/routing.sh`.
- **Ревизовать**: routing из генератора (T3) — согласованность правил.
- **DoD**: netns routing-тест зелёный; на R2S — blocked-финал; коммит.

### T8 — Боевой рантайм xray + procd (Stage 3) [T3 netns + BLOCKED-real]

- `procd` init-скрипт, запуск xray из сгенерированного конфига; supervise/respawn.
- netns-интеграция против **локального** Reality-сервера (пара в netns): туннель работает, kill-switch (kill xray → fail-closed блок), leak-тест.
- **Проверка**: T3 — netns с локальной Reality-парой. **Реальный VPNON = blocked** (нужна ссылка).
- **Тесты добавить**: `test/integ/{tunnel,killswitch,leak}.sh`.
- **Ревизовать**: T7 (firewall), T4 (service.toggle → реальный запуск).
- **DoD**: netns-тесты зелёные; коммит; реальное подключение помечено blocked.

### T9 — Этап 4: DNS split + DoH + anti-DPI + IPv6 + kill-switch опции [T4 + T3 netns]

- Расширить генератор (dns split RU/DoH, uTLS fingerprint, XHTTP padding), UCI, UI-tooltips, IPv6-блок, kill-switch toggle.
- **Проверка**: T4 — обновлённые snapshot генератора; T3 — netns: dns-split, ipv6-block, kill-switch fail-closed.
- **Тесты добавить**: `test/integ/{dns,ipv6}.sh`; новые golden-фикстуры.
- **Ревизовать**: **обязательно** golden-фикстуры генератора (T3) и netns (T7/T8) — поведение расширено.
- **DoD**: все unit+netns зелёные; коммит.

## Зависимости

```
T0 → T1
T0 → T2 → T3 → T4 → T5
T3 → T7 → T8 → T9
T4 → T6(blocked)
T8 → real-VPNON(blocked), R2S(blocked)
```

## Реалистичный объём этого автономного запуска

Полностью автономно и с тестами: **T0, T2, T3, T4** (ядро: скелет + парсер + генератор + rpcd).
Частично/scaffold + blocked-пометки: **T1** (dev-VM скрипты), **T5** (UI + чек-лист), **T7–T9**
(netns-харнесс зависит от привилегированного Linux-контейнера; пишу + пробую запустить).
**T6** и реальные подключения/железо — blocked.

## Definition of Done (общий)

- `.context/` полный; `make lint && make check && make test-unit` зелёные на каждом коммите.
- Каждый шаг (кроме T1) имеет тесты; ревизии тестов выполнены по секциям «Ревизовать».
- `.claude/.verify-state.json` обновлён перед каждым коммитом.
- Blocked-шаги задокументированы с командами в отчёте `.claude/reports/`.
- Dev-log записан.
