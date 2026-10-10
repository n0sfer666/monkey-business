# Тестовая стратегия

Полная версия (уровни по шагам, переосмысление тестов, границы blocked) —
в `.context/specs/2026-06-05-monkey-business-vpn-client.md`, раздел «Тестовая стратегия».

## Кратко
- **Backend на ucode** → host-тестируемая чистая логика (парсер/генератор) без железа.
- **Unit/snapshot** (T4): `test/unit/*.uc` через `test/harness.uc`, фикстуры в `test/fixtures/`.
  Каждый файл заканчивается `exit(run());`. Прогон: `make test-unit` (в контейнере).
- **Интеграция** (T3): netns-харнесс `test/integ/*.sh` (ip netns + nft + xray + локальный upstream).
  Прогон: `make test-integ` (Linux/привилегированный контейнер).
- **Snapshot:** golden JSON в `test/fixtures/xray_*.json`; при изменении генератора — обновить.
- **LuCI JS** (T2): `test/js/*.test.js` под `node --test` (node в образе), гоняется в `make test-unit`.
  Загрузчик `test/js/luci.js` подменяет `baseclass.extend` и `_()`, резолвит только
  `view.monkey-business.*`; модуль, тянущий LuCI (`uci`, `ui`, `dom`), падает — так `model/` держится
  без DOM. Вид и поведение экранов — ручной runbook на R2S (`specs/2026-10-10-compact-ui-runbook.md`).
- **Приёмка UI** (T3): критерии `specs/2026-10-10-compact-ui-acceptance.md`, последний аудит
  `specs/2026-10-10-compact-ui-audit.md`. Playwright Chromium + WebKit против dev-VM; борды макета
  рендерятся локально (`support.js` = dc-runtime, состояния через `window.__dcSetProps`). WebKit
  обязателен: Safari не фокусирует кнопки по Tab и клику — ловушки фокуса и возврат на триггер
  ломаются только там.

## Правило переосмысления тестов
Шаг, меняющий контракт предыдущего, ОБЯЗАН ревизовать его тесты:
- схема server-объекта (парсер) → golden генератора;
- расширение генератора (этап 4: DNS/anti-DPI/IPv6) → snapshot + netns;
- UCI-контракт → rpcd-хендлеры и их тесты.

## Что тестировать
- Парсер: happy/malformed/empty/boundary, все форматы (base64/uri/clash-stub/json).
- Генератор: корректный Xray JSON для каждого routing-режима; валидная структура.
- rpcd: каждый метод на мок-входе возвращает корректную структуру.
- netns: routing (RU direct/зарубеж VPN), kill-switch fail-closed, leak (IP/DNS), IPv6-блок, DNS-split.

## Что НЕ автоматизируется (blocked)
Реальное подключение к VPNON, прошивка/перф на R2S, визуальная проверка LuCI на живой VM.
