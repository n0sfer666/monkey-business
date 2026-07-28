# Архитектура

```
┌─────────────────────────────────────────────┐
│  LuCI client-side JS (luci/)                 │  dashboard / servers / settings / first-run
├─────────────────────────────────────────────┤
│  rpcd-сервис (src/rpcd/*.uc)                 │  ubus-методы: status, servers.*, subscription.*,
│                                              │  geo.update, config.apply, service.toggle
│                                              │  connect → selectWorking (проба серверов по порядку)
├─────────────────────────────────────────────┤
│  UCI /etc/config/monkey-business             │  источник правды
├─────────────────────────────────────────────┤
│  Генератор (src/generator/xray.uc)           │  UCI-структура → Xray JSON (+ generateProbe)
│  Парсер (src/parser/subscription.uc)         │  подписка → нормализованные серверы
│  Lib (src/lib/*.uc)                          │  общие утилиты (uri, validation)
├─────────────────────────────────────────────┤
│  procd init → Xray-core                       │
│  boothealth (mb-boothealth)                   │  ext4-rootfs: детект unclean/ro-remount, 0 периодики
│  cron watchdog (watchdog.sh+probes+phases)    │  1/мин; reconnect → failover → fail-open direct
│  cron nicwatch (nicwatch.sh) + nicfw.sh       │  1/мин; залипание TX eth1 (RTL8153B) → bounce/re-bind
│  nftables TPROXY (scripts/firewall/)          │  перехват TCP+UDP; :53 → dns-in (не tproxy)
│  nft direct-bypass (ruset.sh → mb_ru4/mb_ru6) │  RU-CIDR минуют tproxy в ядре (быстрый путь)
│  Xray transparent DNS (dns-in :5300 + split)  │  клиентский :53 редиректится в dns-модуль
└─────────────────────────────────────────────┘
```

## Потоки данных
1. **Подписка:** URL → `subscription.uc` (auto-detect формата) → нормализованный список серверов → UCI.
2. **Apply / connect:** UCI → `selectWorking` (пробует серверы по порядку списка, первый рабочий →
   тег в `/etc/monkey-business/active`) → `xray.uc` → Xray JSON → procd restart → nftables TPROXY.
3. **Маршрутизация:** два слоя. Ядро: RU-CIDR из nft-сетов `mb_ru4`/`mb_ru6` не попадают в TPROXY
   (`direct_bypass=1`, дефолт) — быстрый путь, без прохода через xray. Xray: geoip/geosite →
   RU/CN/private direct, остальное в туннель (default bypass-RU) — safety-net для того, что не попало
   в nft-сет. Sniffing с `routeOnly:true`: снифнутый домен идёт только в матчинг правил, адрес не
   подменяется → direct-аутбаунд коннектится по оригинальному IP.
4. **DNS:** клиентский :53 НЕ уходит под tproxy (raw-UDP-53 через прокси не ходит), а редиректится
   firewall'ом на dns-инбаунд Xray (:5300) → dns-аутбаунд → dns-модуль со сплитом (регион → `direct_dns`
   напрямую, остальное → DoH в туннеле). Домен VPN-сервера резолвится direct'ом (иначе bootstrap-дедлок).
   dnsmasq остаётся резолвером самого роутера.
5. **Отказоустойчивость:** watchdog (cron 1/мин) — liveness через socks + сверка exit-IP ≠ домашнего.
   3 провала → reconnect (`kill xray`, procd поднимает; kill-switch держится) → не помогло 2 раза →
   failover (`ubus config_apply` → `selectWorking` выберет другой сервер) → не помогло → `init.d stop`
   (flush.sh снимает kill-switch, LAN на direct) + backoff-попытки восстановления.
6. **Железо (LAN):** `eth1` = USB-адаптер RTL8153B (r8152) и единственный член `br-lan`. Пакетная
   прошивка v2 подвешивает TX-очередь (openwrt#22130) → `nicfw.sh` ставит v1 (нужна перезагрузка,
   пинится в sysupgrade.conf), `nicwatch.sh` (cron 1/мин, 2 чтения sysfs) страхует: реагирует только
   если tx_errors растёт, а tx_packets — нет; эскалация bounce → USB re-bind → backoff.
7. **Загрузка файлов:** `fetch.sh` (`mb_fetch`) — direct, при провале фолбэк через socks xray
   (`127.0.0.1:10808`). Трафик роутера идёт мимо tproxy, поэтому упирается в блокировки провайдера
   (`raw.githubusercontent.com`), из-за чего RU-сет не собирался и весь RU-трафик уходил в туннель.

## Границы тестируемости
- `parser` и `generator` — чистые функции на структурах → host unit/snapshot тесты (ucode-харнесс).
- `rpcd` — хендлеры тестируются напрямую на мок-входе; ubus/uci-привязка тонкая.
- Сеть (TPROXY/DNS/kill-switch/leak) — netns-харнесс; финал на R2S.

## Ключевые решения
Полная спецификация и обоснования: `.context/specs/2026-06-05-monkey-business-vpn-client.md`.
