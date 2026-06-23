---
date: 2026-06-18
tags:
  - investigation
  - routing
  - dns
  - performance
status: in-progress
---

# Лаги на direct-ресурсах под VPN (whitelist не помогает)

## Симптом
Ресурс добавлен в whitelist (`custom_direct`, via direct), но всё равно лагает.
Выключаешь VPN — всё ок.

## Ключевой архитектурный факт
В этой схеме direct-трафик **НЕ обходит Xray на уровне ядра**. TPROXY заворачивает в
Xray весь LAN-трафик (TCP+UDP), а «direct» — это лишь выбор `freedom`-outbound внутри
Xray. То есть Xray всегда в датапути, даже для whitelisted-ресурсов.

---

## Гипотезы (по убыванию вероятности)

### H1 — DNS direct-ресурса резолвится через туннель → «далёкий» IP (главная)
`buildDns()` (`src/generator/xray.uc:107`): в direct-DNS сервер попадают только
`["geosite:private", "geosite:"+region]`. Домены из `custom_direct` туда НЕ добавляются.
Следствие:
1. Трафик домена идёт `direct` (правило роутинга). ✅
2. DNS-запрос домена не матчит direct-DNS → уходит на `doh_url` (1.1.1.1) через туннель.
3. 1.1.1.1 по умолчанию не шлёт EDNS Client Subnet → CDN геобалансирует по точке выхода
   VPN → отдаёт далёкий/Anycast узел.
4. Браузер коннектится напрямую к далёкому CDN-узлу → высокий RTT → лаги.
5. VPN off → DNS провайдера → ближайший edge → быстро.

Это разрыв между *split роутинга* и *split DNS*. Симптом совпадает на 100%.

**Проверка:** `dig @<router_lan_ip> <domain> +short` (через туннель) vs
`dig @<isp_dns> <domain> +short` (напрямую). Разные IP + хуже mtr/ping до туннельного →
подтверждено.

### H2 — QUIC / HTTP-3 (UDP 443) ломает direct-по-домену
Снифинг `["http","tls","quic"]`, TPROXY ловит UDP. Если SNI зашифрован (ECH) или QUIC
Initial фрагментирован — домен не достаётся → правило `custom_direct` (по домену) не
матчит → с `domainStrategy:IPIfNonMatch` матчинг по IP → IP нет в direct → в туннель.
Happy-Eyeballs: HTTP/3 в туннель, HTTP/2 direct → плавающие лаги. UDP-TPROXY на RK3328 —
джиттер.
**Проверка:** временно дропнуть UDP/443 → откат на TCP-TLS. Лаги ушли → это QUIC.

### H3 — sniffing `routeOnly:false` → freedom повторно резолвит домен через туннельный DNS
`sniffing.routeOnly:false` (`xray.uc:28`): снифнутый домен подменяет destination outbound.
`freedom` резолвит его через dns-модуль → тот же split → не в RU → DoH-в-туннеле → далёкий
IP. Тот же корень, что H1, через другой механизм. Вариант лечения — `routeOnly:true`.

### H4 — Xray всегда в датапути → CPU RK3328 (без AES-NI) добавляет латентность direct-у
Софтовое крипто, одно ядро сатурируется. direct-флоу тоже идут через event-loop Xray
(dokodemo-door → freedom) → CPU-давление туннеля добавляет очередь и direct-пакетам.
**Проверка:** `%CPU` процесса xray в момент лага (`top`).

### H5 — MTU/MSS на проксированном direct-пути + холодный DNS-кэш
direct переотправляется freedom; битый PMTU без MSS-clamp → крупные пакеты застревают
(`ping -M do -s 1472`). DoH-в-туннеле на каждый не-RU домен = двойной RTT, холодный кэш →
медленная первая загрузка.

---

## Мониторинг (минимальная нагрузка)
Принцип: on-demand снапшоты вместо постоянного частого поллинга; тяжёлые логи включать
только на время диагностики и откатывать (беречь flash).

- **Ур.1 (точечно):** Xray access-log `log:{access:"/tmp/xray-access.log"}` → строки
  `accepted tcp:domain:443 [tproxy-in -> direct]` показывают снифнутый домен + выбранный
  outbound. Закрывает H1/H2/H3 одним grep. После — откатить на `warning` без access.
- **Ур.2 (one-shot):** скрипт `mb-diag <domain>`: dig туннель vs ISP + mtr до каждого IP +
  вердикт «далёкий узел да/нет».
- **Ур.3 (лёгкий пассив):** nft counters (хук `MB_NFT_COUNTER` уже есть); Xray StatsService
  (proxy vs direct uplink/downlink, поллинг 5–10с); `conntrack -L|grep <ip>` по запросу;
  сэмпл load-avg + %CPU xray в tmpfs-кольцо.

---

## Geo (ответ на вопрос про другие geosite/geoip)
1. region-local сейчас = `geoip:private,geoip:ru` + `geosite:private,geosite:category-ru`.
   Многие RU-сервисы на глобальных CDN (Cloudflare/Fastly/Google) не в `geoip:ru` /
   `category-ru` → тоннелятся → ловят H1.
2. Альтернативы под RU-bypass: itdoginfo/re-filter, antifilter.download (как `ext:` или
   мердж в свой .dat). Loyalsoldier — ок как дефолт.
3. Главное: синхронизировать DNS-split с роутинг-split. Всё, что в `direct` (включая
   `custom_direct` и расширенные geo), должно резолвиться direct-DNS, иначе H1 бьёт
   независимо от полноты geo.

---

## План проверки (от вероятного к менее)
1. `mb-diag <домен>`: access-log (direct/proxy?) + dig-diff + mtr → отсекает H1/H2/H3.
2. Дроп UDP/443 → H2.
3. `top` на xray под нагрузкой → H4.

## Лог проверок
- 2026-06-18: первый `dig @127.0.0.1 2sub.movie` с Mac → timeout. Ошибка теста, а не
  диагноз: 127.0.0.1 на маке = сам мак, там DNS-сервера нет. Запрос надо слать на LAN-IP
  роутера (firewall редиректит :53→:5300 только для `iifname br-lan`).
- 2026-06-18: `dig @192.168.1.1` vs `@8.8.8.8` → ОДИНАКОВЫЕ IP. `2sub.movie`/`2sub.net`
  → 176.114.85.18 (Selectel, RU). `2sub.pro` → Cloudflare. Домены НЕ гео-балансируются →
  **H1 для этих доменов отпадает** (туннельный DNS не отдаёт «далёкий» IP).
- 2026-06-18: уточнение — лагает **не страница, а видео-стрим**. Сервис тянет видео с
  ОТДЕЛЬНЫХ CDN-хостов (другой домен, не покрыт digом/whitelist). Фокус смещается на
  идентификацию стриминговых хостов и их outbound (direct/proxy) + throughput туннеля.
- 2026-06-18: `logread -f` → `Failed to find log object: Not found` (сломан logd/ubus
  «wedge» на железе). Лог Xray через logread недоступен → шлём access-log в ФАЙЛ.

## Текущие ведущие гипотезы (после сужения)
- **H-CDN**: видео-CDN-хост НЕ в geoip:ru и НЕ в custom_direct → уходит в туннель. Если
  хост RU → hairpin через заграницу; если иностранный CDN → throughput туннеля = потолок.
- **H4 (CPU/throughput)**: видео — это сустейн-битрейт. RK3328 без AES-NI на софт-крипто
  даёт десятки Мбит/с; стрим в туннеле упирается в CPU/throughput → буферизация.
- Whitelist домена страницы (`2sub.movie`) НЕ влияет на видео — стрим с другого хоста.

## РЕШАЮЩИЕ находки (2026-06-18, вторая сессия)
- Точка выхода — 🇪🇪 Эстония (RTT до РФ низкий → лаг видео это throughput, не расстояние).
- access-log Xray для dokodemo-door/TPROXY пишет ИСХОДНЫЙ IP, не снифнутый домен
  (`grep '[a-zA-Z]'` по 896 строкам = 0 доменов). Тег `-> direct/proxy` при этом валиден.
  ВЫВОД: access-log нельзя использовать для маппинга домен→outbound; для этого нужен
  `check_exit` / header-тест / exit-IP.
- **whitelist по домену РАБОТАЕТ.** Flip-тест: `custom_direct='ru.wikipedia.org'` →
  `config_apply` → curl → заголовок `GeoIP=RU:St_Petersburg`, `x-client-ip=87.248.239.54`
  (реальный RU-IP) вместо прежнего `GeoIP=EE`. Снифинг SNI жив для TCP-TLS.
- Гипотеза «снифинг сломан глобально» — ОПРОВЕРГНУТА.
- ubus: объект `monkey-business` (НЕ `luci.monkey-business`), метод `config_apply` (НЕ
  `config.apply`). `config_apply` РЕГЕНЕРИТ xray.json из UCI → затирает ручные правки
  (в т.ч. инъекцию access-пути sed'ом). Полезные методы: `set_routing`, `check_exit`.
- ВНИМАНИЕ: в ходе теста `custom_direct` перезаписан на `ru.wikipedia.org` — исходный
  список пользователя затёрт, нужно восстановить.

## Сузившийся корень
whitelist работает для TCP-TLS → исходная жалоба объясняется одним из:
1. в whitelist добавлен домен СТРАНИЦЫ (`2sub.movie`), а видео тянется с ДРУГОГО CDN-хоста,
   которого в списке нет;
2. видео идёт по QUIC/HTTP-3 (UDP 443; в логе 286 udp-строк) — снифинг QUIC не достаёт
   SNI → роутинг по IP → не в geoip:ru → туннель → throughput-лаг. Whitelist по домену
   QUIC не ловит.
Следующий шаг: DevTools Network при проигрывании → хост(ы) видео-CDN + протокол (h2/h3).
</content>
</invoke>
