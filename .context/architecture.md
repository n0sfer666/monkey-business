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
│  boothealth (mb-boothealth + beat)            │  ext4-rootfs: sync-гигиена + детект unclean/ro-remount
│  cron watchdog (watchdog.sh, 1/мин)           │  проба exit через VPN; провал → fail-open direct
│  nftables TPROXY (scripts/firewall/)          │  перехват TCP+UDP; :53 → dns-in (не tproxy)
│  Xray transparent DNS (dns-in :5300 + split)  │  клиентский :53 редиректится в dns-модуль
└─────────────────────────────────────────────┘
```

## Потоки данных
1. **Подписка:** URL → `subscription.uc` (auto-detect формата) → нормализованный список серверов → UCI.
2. **Apply:** UCI → `xray.uc` → Xray JSON → procd restart → nftables TPROXY.
3. **Маршрутизация:** geoip/geosite → RU/CN/private direct, остальное в туннель (default bypass-RU).
4. **DNS:** клиентский :53 НЕ уходит под tproxy (raw-UDP-53 через прокси не ходит), а редиректится
   firewall'ом на dns-инбаунд Xray (:5300) → dns-аутбаунд → dns-модуль со сплитом (регион → `direct_dns`
   напрямую, остальное → DoH в туннеле). dnsmasq остаётся резолвером самого роутера.

## Границы тестируемости
- `parser` и `generator` — чистые функции на структурах → host unit/snapshot тесты (ucode-харнесс).
- `rpcd` — хендлеры тестируются напрямую на мок-входе; ubus/uci-привязка тонкая.
- Сеть (TPROXY/DNS/kill-switch/leak) — netns-харнесс; финал на R2S.

## Ключевые решения
Полная спецификация и обоснования: `.context/specs/2026-06-05-monkey-business-vpn-client.md`.
