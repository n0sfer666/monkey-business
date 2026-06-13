# План: local_region "other" + ревью + docs (2026-06-13)

Спека: `.context/specs/2026-06-13-other-region-review-docs.md`.
Проверки (из `.context/checks.md`): `make test` = lint + check + test-unit (Docker, доступен).

## Task 1 — Фича local_region "other" (F1)
**Файлы:** `src/generator/xray.uc`, `luci/htdocs/luci-static/resources/view/monkey-business/settings.js`,
`test/unit/generator_test.uc`.
**Что:**
- `xray.uc/buildRouting`: ранняя ветка `region == "other"` → passthrough
  (ipv6-block если включён, затем `{network:"tcp,udp", outboundTag:"direct"}`); mode и custom — игнор.
- `xray.uc/buildDns`: ранняя ветка `region == "other"` → `{ servers:[direct_dns||"223.5.5.5"], queryStrategy }`.
- `settings.js`: `region.value('other', _('Other — all traffic direct (no VPN routing)'))`; tooltip.
- `generator_test.uc`: +4 теста (passthrough, +ipv6, +global+custom без proxy, buildDns(other)).
**Проверка (T4):** `make test-unit` зелёный, новые тесты проходят; golden-снапшоты (ru) не изменились.
**Зависимости:** нет.

## Task 2 — Независимое ревью каждого модуля (F2, фаза сбора)
**Что:** запустить независимые ревью-субагенты (свежий взгляд) по 4 группам модулей
(backend-логика / рантайм-device / frontend / dev-build-test). Каждый возвращает структурный
список находок (severity, файл:строка, проблема, предлагаемый фикс).
**Файлы:** только чтение на этом шаге. Результат — сводный список находок.
**Проверка:** —
**Зависимости:** независимо (можно параллельно с Task 1).

## Task 3 — Применить фиксы из ревью (F2, фаза фиксов)
**Что:** применить все найденные исправления (баги, безопасность, shellcheck, ucode-идиомы,
DRY/KISS, мёртвый код). НЕ трогать gotcha-комментарии. Спорные/среднериск. — в отчёт.
**Файлы:** по итогам Task 2 (любые исходники/скрипты/тесты).
**Проверка (T2):** `make test` зелёный после каждой пачки фиксов; при правке генератора/парсера —
сверить/обновить golden-снапшоты.
**Зависимости:** Task 2.

## Task 4 — README (F3)
**Файлы:** `README.md`.
**Что:** перестроить: описание → Install (ipk/deploy на роутер) → Development (контейнерные проверки,
dev-VM) → Troubleshooting (все dev-кейсы из `.context/notes/dev-env.md` + текущего README + dev-log) →
Feedback (GitHub Issues/Discussions) → License (GPL-3.0). Англ., лаконично.
**Проверка (T1):** команды сверены с Makefile/скриптами; ссылки валидны.
**Зависимости:** желательно после Task 3 (troubleshooting может пополниться находками ревью).

## Task 5 — LICENSE (F4)
**Файлы:** `LICENSE` (новый).
**Что:** полный канонический текст GPL-3.0.
**Проверка (T0):** наличие файла, заголовок корректен.
**Зависимости:** нет.

## Task 6 — NanoPi install guide (F5)
**Файлы:** `docs/install-nanopi.md` (новый).
**Что:** развёрнутый гайд (ImmortalWrt уже стоит): платформа/место, рантайм-deps, два пути
(ipk через SDK / `deploy-vm.sh` по SSH на R2S), geo, подписка/серверы, включение, проверка сплита,
проблемы R2S. Сослаться из README.
**Проверка (T1):** команды сверены с `scripts/deploy-vm.sh`, `geo.sh`, Makefile.
**Зависимости:** после Task 4 (ссылка из README) — мягкая.

## Definition of Done
- F1: passthrough-конфиг без невалидных geo-категорий; +4 unit; `make test` зелёный; golden(ru) не тронут.
- F2: ревью по всем модулям; фиксы применены или вынесены в отчёт; `make test` зелёный.
- F3: README перестроен по структуре; GPL-3.0.
- F4: файл LICENSE с полным GPL-3.0.
- F5: `docs/install-nanopi.md` написан, команды сверены.
- `.claude/.verify-state.json` записан; dev-log + отчёт.

## Проверки (сводно)
- Базовая каждая итерация: `make test` (lint + check + test-unit) в Docker.
- T4 для F1 (регрессионные unit на passthrough).
- T3 (dev-VM/R2S) — blocked в прогоне (нет запущенной VM); инструкции/тесты готовы для ручного прогона.

## Порядок исполнения
1 (фича) ∥ 2 (ревью-сбор) → 3 (фиксы) → 4 (README) → 6 (nanoPi) ; 5 (LICENSE) в любой момент.
