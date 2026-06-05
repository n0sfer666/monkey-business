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
