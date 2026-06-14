# План: независимое ревью + RU-документация с nushell (2026-06-14)

Спека: `.context/specs/2026-06-14-independent-review-ru-docs.md`.

## Tasks

### T1 — Независимое ревью (4 группы, свежий взгляд)
- Запустить 4 независимых субагента-ревьюера (по группам модулей), параллельно. Каждый — read-only,
  возвращает структурный список находок: `{file, line, severity, category, claim, fix?}`.
  - R1 backend-логика: `src/parser/subscription.uc`, `src/lib/uri.uc`, `src/generator/xray.uc`, `src/rpcd/handlers.uc`.
  - R2 рантайм/device: `root/usr/share/rpcd/ucode/monkey-business.uc`, `root/etc/init.d/monkey-business`,
    `root/usr/share/monkey-business/geo.sh`, `scripts/firewall/apply.sh`, `scripts/firewall/flush.sh`, `root/etc/config/monkey-business`.
  - R3 frontend: `luci/.../dashboard.js`, `servers.js`, `settings.js`, `menu.d`, `acl.d`.
  - R4 dev/build/test: `Makefile`, `scripts/*.sh`, `Dockerfile.test`, `Dockerfile.integ`, `test/*`.
- Свести находки, дедуплицировать, перепроверить каждую лично (отсечь ложные).
- **Зависимости:** нет (стартовая).
- **Проверка:** T1 (ручная верификация каждой находки по коду).

### T2 — Фиксы реальных находок
- Исправить все подтверждённые баги/безопасность/корректность. Каждый фикс — минимальный, по
  конвенциям (`conventions.md`: без комментариев, POSIX sh, ucode export-в-конце, ≤200 строк).
- Где затронута логика — добавить/обновить unit-тест (T4) и сверить golden.
- Файлы: по результатам T1 (потенциально любой из списка выше + `test/unit/*`).
- **Зависимости:** T1.
- **Проверка:** после КАЖДОГО фикса `make lint && make check && make test-unit`; где затронут
  generator/parser/firewall — `make test-integ`. Записать `.claude/.verify-state.json`.

### T3 — RU README
- `README.ru.md`: полный перевод `README.md` (структура 1:1). Внутренние ссылки → RU-аналоги.
- В `README.md` и `README.ru.md` добавить кросс-линк языка вверху.
- **Зависимости:** нет (можно параллельно с T1/T2, но коммитить после, чтобы EN отражал фиксы).
- **Проверка:** T1 (вычитка, ссылки, соответствие командам).

### T4 — RU install-nanopi
- `docs/install-nanopi.ru.md`: полный перевод `docs/install-nanopi.md`. Ссылка на `README.ru.md`.
- Кросс-линк языка вверху EN и RU.
- **Зависимости:** нет.
- **Проверка:** T1.

### T5 — nushell-строки (EN + RU, оба дока)
- Добавить nushell-вариант (отдельный ```nu блок с подписью) для хост-команд с env-var префиксами:
  - `scripts/deploy-vm.sh` вызов (README Install A, install-nanopi §2) → `with-env { … } { sh scripts/deploy-vm.sh }`.
  - `export MB_SDK_DIR=…; make package` (README Install B, install-nanopi §2 alt) → `$env.MB_SDK_DIR = "…"; make package`.
  - `MB_VM_HTTP_PORT=NNNN make dev-up` (README dev VM) → `with-env { MB_VM_HTTP_PORT: "NNNN" } { make dev-up }`.
  - проверить остальные env-префиксы (`MB_IMMORTALWRT_URL` и пр. — если в доке как команда).
- НЕ добавлять для router-команд (`#`/ssh/apk/nft/ubus/logread) и для команд без отличий.
- **Зависимости:** T3, T4 (чтобы добавить и в RU-файлы).
- **Проверка:** T1 (синтаксис nushell, единообразие EN/RU).

### T6 — Финальная проверка + артефакты
- `make test` (и `make test-integ` если затронута сеть) — зелёный.
- Отчёт `.claude/reports/2026-06-14-independent-review-ru-docs.md`: находки (исправлено/вынесено),
  severity, изменённые файлы, коммиты.
- dev-log `/Users/n0sfer/wiki/dev-log/2026/06/2026-06-14.md`.
- Обновить `.context/` если найдено новое о проекте.
- **Зависимости:** T1–T5.

## Definition of Done
- Ревью по 4 группам; реальное исправлено под `make test`, спорное — в отчёт.
- `make test` зелёный; `test-integ` зелёный где применимо.
- `README.ru.md`, `docs/install-nanopi.ru.md` созданы, кросс-линки EN↔RU.
- nushell-строки во всех host-командах с отличием (EN+RU), без лишнего дублирования.
- Отчёт + dev-log записаны.

## Проверки (команды)
- `make lint` (T1) · `make check` (T1) · `make test-unit` (T2/T4) · `make test-integ` (T3) · `make test` (всё).

## Коммиты (Conventional, автокоммит по custom-flow)
- `fix(...): ...` — по группам находок (scope: parser/generator/rpcd/luci/firewall/dev).
- `docs: add Russian README and NanoPi guide, nushell command variants`.
