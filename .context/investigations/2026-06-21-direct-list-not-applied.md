---
date: 2026-06-21
tags:
  - investigation
  - routing
  - firewall
  - direct-list
status: resolved-diagnosis
---

# Direct-лист игнорируется: IP 81.85.75.40 не идёт direct

## Симптом (как сообщён)
IP в `custom_direct` не маршрутизируется напрямую. При VPN on `ping 81.85.75.40` —
мгновенный timeout, на удалённом сервере tcpdump не видит ICMP (признак drop в nftables).
При VPN off всё работает. Ранее так же «терялись» целые RU-подсети в direct-листе.

## Архитектурный факт
В nftables **нет direct-bypass-set**. `scripts/firewall/apply.sh` в prerouting обходит
TPROXY только для приватных диапазонов и порта 53; весь остальной трафик заворачивается в
Xray. `custom_direct` существует **только как Xray-правило** (`freedom`-outbound). На уровне
ядра direct-листа нет вовсе.

## Находки (верифицированы на боевом R2S, 192.168.1.1)

### Причина №1 — kill-switch дропает ICMP (= наблюдаемый симптом). НЕ код-баг, by design
`apply.sh:32-40,53`. Живой `nft list table inet monkey_business`:
```
chain prerouting { ... iifname "br-lan" meta l4proto { tcp, udp } tproxy to :12345 ... }
chain forward    { ... iifname "br-lan" drop }   # без фильтра протокола
```
ICMP не матчит tproxy-правило (только tcp/udp) → не заворачивается → forward → **drop**.
Так дропается `ping` к ЛЮБОМУ публичному IP, в direct-листе он или нет (kill-switch про
`custom_direct` ничего не знает — это Xray-слой). TCP/UDP к тому же IP не дропается:
заворачивается в Xray, терминируется локально, `freedom` шлёт с роутера через OUTPUT.
**Вывод: `ping` не валиден для проверки direct. Проверять `curl`/`nc`.**

### Причина №2 — sniffing routeOnly:false обходит IP-правило (реальный баг для TCP-TLS)
`src/generator/xray.uc:28`. Живой `xray.json`: `"routeOnly": false` (стр. 26, 43).
При destOverride[http,tls,quic] Xray снифает SNI и подменяет destination на домен; с
`domainStrategy:IPIfNonMatch` IP-правило матчится против **переразрешённого** через DNS
адреса (не-RU домен → DoH-в-туннеле). Если домен резолвится в другой IP, чем исходный
(CDN/geo-balance/round-robin) → IP-правило не матчит → catch-all → туннель. Объясняет
«RU-подсети игнорировались» и «whitelist по домену работает, по IP — нет».
**Фикс: routeOnly:true** — снифнутый домен идёт только в роутинг, исходный IP сохраняется
для матчинга IP-правил и для direct-дилинга; доменные правила продолжают работать.

### Причина №3 — порядок ipv6_block перед custom-правилами (edge)
`xray.uc:176` (было — до custom). `{ip:["::/0"],block}` добавлялся первым → IPv6 в
direct-листе блокировался раньше своего direct-правила. **Фикс: custom-правила перед
ipv6-block.** (На боевом устройстве `ipv6_block` сейчас не выставлен → ::/0 в живом дампе
отсутствует; фикс защитный.)

## Проверено и НЕ баг
- Формат IP/CIDR/comma: `classifyList`/`isIpLike` (`xray.uc:126-154`) — прогон в контейнере:
  одиночный IP, `/16`, список через запятую парсятся верно (`replace` в ucode глобальный).
- Путь UCI→Xray синхронен: живой `xray.json` содержит `{"ip":["81.85.75.40"],"direct"}`
  перед proxy-catch-all. Рассинхрона «попал в один слой, не в другой» нет (второй слой —
  nft — для `custom_direct` отсутствует by design).
- `ip rule`/`route`: `fwmark 0x1 → table 100 → local default dev lo` — штатный TPROXY
  policy-routing, отдельной туннельной таблицы нет, misroute для direct не возникает.

## Сделано
- `routeOnly:false→true` (`xray.uc:28`); custom-правила подняты над ipv6-block.
- Обновлены golden-снапшоты + регресс-тест порядка. `make lint/check/test-unit` — green.
- Коммит `e783b83`.

## Осталось (поведенческая T3 фикса)
Деплой на боевой роутер (`make deploy HOST=root@192.168.1.1` — рестарт сервиса+firewall) и
`ubus call monkey-business check_exit` / curl-флип до/после для домена, чей IP в direct-листе.
Не выполнено: рестарт боевого шлюза требует согласования времени с пользователем.
