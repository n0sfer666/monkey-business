# Архитектура

```
┌─────────────────────────────────────────────┐
│  LuCI client-side JS (luci/)                 │  dashboard / servers / settings / first-run
├─────────────────────────────────────────────┤
│  rpcd-сервис (src/rpcd/*.uc)                 │  чистые хендлеры ubus-методов: handlers (мутации),
│                                              │  status, subscription, select, ping, hysteria, uri
│                                              │  connect → selectWorking (проба серверов по порядку)
│  Рантайм плагина (src/runtime/*.uc)          │  всё, что трогает устройство: shell, uci, net,
│                                              │  apply (валидация+atomic install), hysteria, paths
├─────────────────────────────────────────────┤
│  UCI /etc/config/monkey-business             │  источник правды
├─────────────────────────────────────────────┤
│  Генератор (src/generator/xray.uc)           │  UCI-структура → Xray JSON (+ generateProbe);
│    inbounds/outbounds/routing/dns.uc         │  секции конфига по отдельности
│           (src/generator/hysteria.uc)        │  сервер → конфиг hysteria-клиента + socks-аутбаунд
│  Парсер (src/parser/subscription.uc)         │  подписка → нормализованные серверы (vless + hy2)
│           (src/parser/validate.uc)           │  строгая проверка ОДНОЙ ссылки из формы
│  Lib (src/lib/*.uc)                          │  общие утилиты (uri, validation, servermap)
├─────────────────────────────────────────────┤
│  procd init → Xray-core (+ hysteria client)   │  второй инстанс того же сервиса, socks :10810
│  boothealth (mb-boothealth)                   │  ext4-rootfs: детект unclean/ro-remount, 0 периодики
│  cron watchdog (watchdog+probes+recovery+phases)│ 1/мин; лестница soft→hard→failover→full→direct
│  cron nicwatch (nicwatch.sh) + nicfw.sh       │  1/мин; залипание TX eth1 (RTL8153B) → bounce/re-bind
│  nftables TPROXY (scripts/firewall/)          │  перехват TCP+UDP; :53 → dns-in (не tproxy)
│  nft direct-bypass (ruset.sh → mb_ru4/mb_ru6) │  RU-CIDR минуют tproxy в ядре (быстрый путь)
│  Xray transparent DNS (dns-in :5300 + split)  │  клиентский :53 редиректится в dns-модуль
└─────────────────────────────────────────────┘
```

## Потоки данных
1. **Подписка:** URL → `subscription.uc` (auto-detect формата) → нормализованный список серверов → UCI.
1a. **Ссылка из формы:** тот же `normalizeUri` + строгий `validate.uc` (ubus `parse_uri`) → сервер
   раскладывается по полям формы и сохраняется как `source: manual`. В UCI поля лежат плоско
   (`tr_*`, `pbk`/`sid`/`spx`, `obfs_*`) — маппинг в контракт держит `lib/servermap.uc`, чтение
   понимает и прежнюю JSON-схему. Ручные серверы обновление подписки не трогает.
   Решение: `.context/decisions/2026-08-07-server-form-link-import.md`.
2. **Apply / connect:** UCI → `selectWorking` (пробует серверы по порядку списка, первый рабочий →
   тег в `/etc/monkey-business/active`) → `xray.uc` → Xray JSON → procd restart → nftables TPROXY.
2a. **Протоколы.** `vless` (Reality/XHTTP/ws) идёт аутбаундом самого xray; `hysteria2` — отдельным
   процессом рядом, а аутбаунд `proxy` превращается в `socks → 127.0.0.1:10810`. Ниже этой точки
   (маршрутизация, DNS, kill-switch, ядерный обход) о протоколе никто не знает — direct-трафик до
   аутбаунда `proxy` не доходит вовсе. Протокол — свойство сервера: оба вида лежат в одном списке,
   порядок = приоритет, failover перебирает кандидатов сквозь протоколы. Клиент hysteria ставится
   кнопкой на дашборде (`hysteria.sh`), проба кандидата поднимает эфемерный клиент на :10811.
   Решение: `.context/decisions/2026-08-06-hysteria-provider.md`.
3. **Маршрутизация:** два слоя. Ядро: RU-CIDR из nft-сетов `mb_ru4`/`mb_ru6` не попадают в TPROXY
   (производно от сплита: `bypass-local` + регион `ru`) — быстрый путь, без прохода через xray. Xray: geoip/geosite →
   RU/CN/private direct, остальное в туннель (default bypass-RU) — safety-net для того, что не попало
   в nft-сет. Sniffing с `routeOnly:true`: снифнутый домен идёт только в матчинг правил, адрес не
   подменяется → direct-аутбаунд коннектится по оригинальному IP.
4. **DNS:** клиентский :53 НЕ уходит под tproxy (raw-UDP-53 через прокси не ходит), а редиректится
   firewall'ом на dns-инбаунд Xray (:5300) → dns-аутбаунд → dns-модуль со сплитом (регион → `direct_dns`
   напрямую, остальное → DoH в туннеле). Домен VPN-сервера резолвится direct'ом (иначе bootstrap-дедлок).
   dnsmasq остаётся резолвером самого роутера.
5. **Отказоустойчивость:** watchdog (cron 1/мин) — liveness через socks + сверка exit-IP ≠ домашнего.
   3 провала → лестница восстановления (`recovery.sh`), по ступени на тик: soft bounce (`kill` xray,
   procd поднимает) → hard restart (SIGTERM → подтверждённая смерть → SIGKILL → `init.d start`,
   `apply.sh` пересобирает nft/policy-routing) → failover (`ubus config_apply` → `selectWorking`
   выберет другой сервер) → full stop/start (аналог ручного Off/On). На первых трёх kill-switch
   держится. Исчерпали → `init.d stop` (LAN на direct) + backoff-попытки восстановления с failover.
   Решение: `.context/decisions/2026-08-06-recovery-ladder.md`.
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
