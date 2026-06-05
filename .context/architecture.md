# Архитектура

```
┌─────────────────────────────────────────────┐
│  LuCI client-side JS (luci/)                 │  dashboard / servers / settings / first-run
├─────────────────────────────────────────────┤
│  rpcd-сервис (src/rpcd/*.uc)                 │  ubus-методы: status, servers.*, subscription.*,
│                                              │  geo.update, config.apply, service.toggle
├─────────────────────────────────────────────┤
│  UCI /etc/config/monkey-business             │  источник правды
├─────────────────────────────────────────────┤
│  Генератор (src/generator/xray.uc)           │  UCI-структура → Xray JSON
│  Парсер (src/parser/subscription.uc)         │  подписка → нормализованные серверы
│  Lib (src/lib/*.uc)                          │  общие утилиты (uri, validation)
├─────────────────────────────────────────────┤
│  procd init → Xray-core                       │
│  nftables TPROXY (scripts/firewall/)          │  перехват TCP+UDP
│  dnsmasq (split DNS / DoH)                     │
└─────────────────────────────────────────────┘
```

## Потоки данных
1. **Подписка:** URL → `subscription.uc` (auto-detect формата) → нормализованный список серверов → UCI.
2. **Apply:** UCI → `xray.uc` → Xray JSON → procd restart → nftables TPROXY.
3. **Маршрутизация:** geoip/geosite → RU/CN/private direct, остальное в туннель (default bypass-RU).

## Границы тестируемости
- `parser` и `generator` — чистые функции на структурах → host unit/snapshot тесты (ucode-харнесс).
- `rpcd` — хендлеры тестируются напрямую на мок-входе; ubus/uci-привязка тонкая.
- Сеть (TPROXY/DNS/kill-switch/leak) — netns-харнесс; финал на R2S.

## Ключевые решения
Полная спецификация и обоснования: `.context/specs/2026-06-05-monkey-business-vpn-client.md`.
