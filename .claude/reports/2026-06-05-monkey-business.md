# Отчёт: monkey-business (custom-flow, 2026-06-05)

VPN-клиент Reality/VLESS/XHTTP для ImmortalWrt/OpenWrt (NanoPi R2S). Автономный прогон.

## Решения по тестированию (согласованы до кода)
- Backend = **ucode** (host-тестируемая чистая логика).
- Интеграция = **network namespaces** + **реальный xray** (в привилегированном Linux-контейнере, т.к. хост — macOS).
- CI = локально, Makefile-цели. Blocked-шаги (железо/секрет/живая VM) — подготовлены и помечены.

## Выполнено (10 коммитов, все проверки зелёные)

| # | Коммит | Что | Проверка |
|---|--------|-----|----------|
| T0 | a14b50c | репо, `.context/`, скелет, ucode test-харнесс, Docker test-image | lint+syntax+unit |
| T1 | 6a1759c | dev-VM скрипты (QEMU aarch64), package.sh | shellcheck; boot blocked |
| T2 | ad1a5a0 | парсер подписки + URI-lib (base64/uri-list, auto-detect) | **14 unit** |
| T3 | d3fc0b6 | генератор UCI→Xray JSON, UCI-схема, golden snapshot | **9 unit** |
| T4 | f87b190 | rpcd-хендлеры (mock-ctx), рантайм-плагин | **11 unit** |
| T7 | afa8f85 | TPROXY nftables ruleset + netns-перехват | **netns integ** |
| T9 | 051bc57 | этап-4: DNS split, XHTTP padding, IPv6-блок | **+6 unit, golden** |
| T5/T8 | 4325952 | LuCI views (dashboard/servers/settings), ACL, menu, procd init | js-syntax; визуал blocked |
| — | f9f1ed5 | валидация конфига **реальным xray** (`Configuration OK`) | **xray -test integ** |
| T6 | 4821756 | capture-sub.sh (захват подписки) | blocked (секрет) |

### Итоговое покрытие
- **43 unit-теста** (parser/generator/rpcd/uri/harness) — `make test-unit`.
- **2 интеграционных** (`make test-integ`):
  - netns: боевой firewall-артефакт перехватывает внешний TCP, приватный — нет, fwmark-rule на месте.
  - xray: реальный Xray 26.3.27 полностью валидирует сгенерированный stage-4 конфиг (reality+xhttp+dns+ipv6+padding, все geo-теги).
- Контракт server-объекта и Xray JSON зафиксированы golden-snapshot'ами (база + stage-4).
- Переосмысление тестов: этап-4 сделан аддитивно — базовый golden остался валиден, добавлен stage-4 golden.

## Blocked (нужен ты / железо)
- **Boot dev-VM** — на хосте нет `qemu-system-aarch64`. Готово: `brew install qemu && make dev-up`.
- **Захват реальной подписки VPNON** (T6) — нужна секретная ссылка: `scripts/capture-sub.sh <url>` (вне репо + ручная санитизация).
- **Визуальная проверка LuCI** — нужна живая VM/устройство; JS синтаксически валиден.
- **Реальное подключение к VPNON, прошивка R2S, перф-тест** — на железе.
- **Сборка ipk** — нужен OpenWrt SDK (`scripts/package.sh`).

## Следующие интеграционные тесты (харнесс-паттерн готов, см. test/integ/tproxy.sh)
- netns-туннель против локальной Reality-пары (xray server+client) — проверка сквозного прохода.
- kill-switch fail-closed (убить xray → marked-трафик заблокирован).
- leak-тест (внешний IP/DNS через туннель), DNS-split, IPv6-блок — в netns.

## Как воспроизвести
```sh
make test         # lint + ucode syntax + js syntax + 43 unit
make test-integ   # netns tproxy + xray config validation (privileged Docker)
```
