# Отчёт: независимое ревью + RU-документация с nushell (2026-06-14)

Спека: `.context/specs/2026-06-14-independent-review-ru-docs.md`.
План: `.claude/plans/2026-06-14-independent-review-ru-docs.md`.

## Метод
4 независимых субагента-ревьюера (свежий взгляд, read-only, без знания находок друг друга) по
группам: backend-логика / рантайм-device / frontend / dev-build-test. Каждая находка лично
перепроверена по коду перед фиксом — часть отсеяна как ложная.

## Выполнено

### F1 — ревью + фиксы

**Исправлено (реальное, под `make test`):**

| Severity | Файл | Что | Коммит |
|----------|------|-----|--------|
| medium (security) | `root/usr/share/rpcd/ucode/monkey-business.uc` | `fetchSubscription`: `umask 077` перед curl/uclient-fetch — tmp с токеном/UUID создаётся 0600 сразу, без окна world-readable во время скачивания (раньше `chmod 600` ставился только ПОСЛЕ fetch). | `c30bdc9` |
| low (doc/contract) | `src/rpcd/handlers.uc` | Комментарий-контракт `ctx` дополнен реально реализованными методами (`setCustomRouting`, `geoStatus`, `geoInstall`, `checkExit`). | `c30bdc9` |
| low (security/race) | `root/usr/share/monkey-business/geo.sh` | `mktemp` для validate-каталога (+err внутри него), `remote_sha`, download-tmp — убран фиксированный `/tmp/mb-geocheck`/`/tmp/mb-sum.$$`/`/tmp/mb-$which.dl` (TOCTOU + предсказуемые имена + клоббер при параллельных validate). | `7236c70` |
| high (coverage) | `scripts/lint.sh` | shellcheck теперь покрывает `root/` — рантайм `geo.sh` раньше не линтовался (16 файлов вместо 15). | `7236c70` |
| medium (bug) | `luci/.../dashboard.js` | `.catch` на flow «Update geo databases»: при сбое `pollGeo` модалка зависала открытой навсегда. | `4a444ca` |
| low | `luci/.../dashboard.js` | `.catch` на «Test latency» (`callPing`); убран мёртвый параметр `labelEl` у `pollGeo`. | `4a444ca` |
| low | `luci/.../servers.js`, `settings.js` | Финальный `.catch` в `handleSaveApply` — молчаливый сбой Save&Apply теперь даёт нотификацию. | `4a444ca` |

**Ложные тревоги (НЕ баги, отсеяны при перепроверке):**
- «`ctx.setCustomRouting/geoStatus/geoInstall/checkExit` вызываются, но не в контракте → runtime fail»
  (R1, critical×4) — рантайм `ctx` их РЕАЛИЗУЕТ (`monkey-business.uc:185,208,224,230`). Реальна была
  только неполнота комментария-контракта (исправлено как low).
- «`handlers.uc:157 added` считает не новые серверы» — UI показывает это как «Servers fetched: N»
  (`servers.js:18`), т.е. = распарсено из подписки. Семантика корректна, не баг.

### F2 — документация (RU + nushell)
- `README.ru.md` — полный перевод README (структура 1:1), кросс-линк EN↔RU вверху обоих.
- `docs/install-nanopi.ru.md` — полный перевод гайда, кросс-линк EN↔RU.
- nushell-блоки добавлены в EN и RU для всех хост-команд с отличающимся синтаксисом (env-var
  префиксы): `deploy-vm.sh` (README+install-nanopi), `export MB_SDK_DIR` (README), `MB_VM_HTTP_PORT`
  (README, inline). Router-команды (`#`/ssh/apk/nft/ubus) и команды без отличий (`make …`) — без nushell.

## Проверка
- `make test` зелёный: shellcheck **16** (geo.sh покрыт), ucode 11, js 3, unit 8/22/7 (+harness selftest).
- `make test-integ` — **не запускался**: затронуты только tmp-хендлинг/UI/линтер; логика
  generator/parser/firewall не менялась → golden-снапшоты и netns не задеты (был зелёным на `cc6c18c`).
- Документация: nushell-покрытие сверено grep'ом; кросс-линки и относительные пути проверены.

## Вынесено в отчёт (НЕ исправлено — спорное/рисковое/отдельная задача)

| Severity | Что | Почему отложено |
|----------|-----|-----------------|
| medium | `dashboard.js` 313 строк (>200) — вынести renderGeo/renderRouting/renderServers в модули. | UI-рефактор, регрессии проверяются только в браузере (T3, dev-VM) — не делал вслепую. |
| low | `handlers.uc` 233 / `xray.uc` 233 строки (>200, в основном комментарии-контракты). | Декомпозиция без явной пользы; риск > выгода. |
| low | `init.d/monkey-business` без `set -u`. | `#!/bin/sh /etc/rc.common` — `set -u` рискует сломать procd/rc.common-функции; дефолты уже подстрахованы (`|| echo`). Сознательно не трогаю. |
| low | `test-split.sh:28` — `$DOMAIN` без JSON-экранирования в `ubus call`. | Dev-only хелпер, аргумент контролирует разработчик; backend всё равно валидирует домен (`/^[a-zA-Z0-9.\-]+$/`). Экранирование в чистом sh хрупко. |
| medium | dev-vm образ без sha256 (`dev-vm.sh`), xray/geo в `Dockerfile.integ` без checksum (supply-chain). | Нужны upstream sha256sums + сверка — отдельная задача (повтор из прошлого отчёта). |
| low | geo-update без `flock` — параллельные «Update geo» гоняют в один state-файл. | mktemp убрал клоббер файлов; сериализация — отдельная мелкая фича. |

## Изменённые файлы
- Фиксы: `root/usr/share/rpcd/ucode/monkey-business.uc`, `src/rpcd/handlers.uc`,
  `root/usr/share/monkey-business/geo.sh`, `scripts/lint.sh`,
  `luci/.../dashboard.js`, `luci/.../servers.js`, `luci/.../settings.js`
- Docs: `README.md`, `README.ru.md` (new), `docs/install-nanopi.md`, `docs/install-nanopi.ru.md` (new)

## Коммиты
- `c30bdc9` fix(rpcd): umask subscription tmp fetch, complete ctx contract doc
- `7236c70` fix(dev): mktemp geo temp files, shellcheck root/ runtime scripts
- `4a444ca` fix(luci): handle geo/ping/save-apply rejections, drop dead param
- `8a2903b` docs: add Russian README and NanoPi guide, nushell command variants
