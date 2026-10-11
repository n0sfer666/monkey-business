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
│  cron subupdate (subupdate.sh)                │  1/мин, по подпискам; ubus subscription_update/_autoswitch
│  nftables TPROXY (scripts/firewall/)          │  перехват TCP+UDP; :53 → dns-in (не tproxy)
│  nft direct-bypass (ruset.sh → mb_ru4/mb_ru6) │  RU-CIDR минуют tproxy в ядре (быстрый путь)
│  Xray transparent DNS (dns-in :5300 + split)  │  клиентский :53 редиректится в dns-модуль
└─────────────────────────────────────────────┘
```

## Потоки данных
1. **Подписка:** URL → `subscription.uc` (auto-detect формата) → нормализованный список серверов → UCI.
   Тот же путь по расписанию: `subupdate.sh` (cron 1/мин) для каждой секции `subscription` (имена из `uci -X show`, анонимные тоже) при её
   `auto_update=1` раз в её `update_interval` (не чаще 300с) зовёт ubus `subscription_update {sub}`;
   после неудачи пауза 900с. Состояние — в tmpfs (`/tmp/mb-subupdate/<id>`), провал одной подписки
   не блокирует остальные; конфиг xray обновление не переприменяет: это делает Apply или watchdog.
   При ≥ 2 подписках тот же тик зовёт `subscription_autoswitch {check}` (только чтение); если активная
   мертва и есть живая — берёт лок watchdog (`/tmp/mb-watchdog/lock`, общий `wdlock.sh`; занят дольше 30с — тик
   пропускается) и зовёт `subscription_autoswitch {deadline}`: событийная запись `active_sub`, причина
   в `/tmp/mb-autoswitch`, apply — только если туннель шёл через мёртвую подписку.
   Сервер подписки несёт опцию `sub` (id секции `subscription`); `source=subscription` без `sub`
   при чтении приписывается легаси-подписке `subscription` (`lib/subs.uc` `serverSub`). Merge
   работает по срезу `sub`: чужие подписки и ручные серверы остаются на своих позициях.
   Спека: `.context/specs/2026-10-08-multi-subscription.md`.
1a. **Ссылка из формы:** тот же `normalizeUri` + строгий `validate.uc` (ubus `parse_uri`) → сервер
   раскладывается по полям формы и сохраняется как `source: manual`. В UCI поля лежат плоско
   (`tr_*`, `pbk`/`sid`/`spx`, `obfs_*`) — маппинг в контракт держит `lib/servermap.uc`, чтение
   понимает и прежнюю JSON-схему. Ручные серверы обновление подписки не трогает.
   Решение: `.context/decisions/2026-08-07-server-form-link-import.md`.
2. **Apply / connect:** UCI → `selectWorking` (параллельный TCP-пинг кандидатов → результат в
   tmpfs `/tmp/mb-ping.json`, ответившие дольше 1с или не ответившие авто-отключены; не прошёл ни
   один — берутся все; затем пробы по порядку, первый рабочий →
   идентичность `<sub>/<tag>`, у ручного `<tag>`, в `/etc/monkey-business/active`) → `xray.uc` →
   Xray JSON → procd restart → nftables TPROXY. Кандидаты (`select.uc` `candidates`): серверы
   `global.active_sub` (пусто/нет секции → первая подписка) + ручные в drag-порядке, затем серверы
   остальных живых подписок по порядку подписок; ручной `disabled='1'` и мёртвые резервные подписки
   (`subAlive`: трафик исчерпан / `expire` прошёл) — не кандидаты. Серверы удалённой подписки
   (сироты) отбрасываются при чтении (`loadServers`) и выпадают при следующей записи списка.
   Смена подписки — `subscription_select` (запись → apply → откат при ошибке).
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
   подменяется → direct-аутбаунд коннектится по оригинальному IP. Литеральные IP/CIDR из
   пользовательского `custom_proxy` заводятся в сеты-исключения `mb_force4`/`mb_force6` (разбор —
   в `apply.sh`) и стоят ВЫШЕ bypass-правил в обеих цепочках: tproxy выше `@mb_ru4 return`, drop
   выше `@mb_ru4 accept`. Без этого RU-адрес из списка «через туннель» отсекался ядром раньше Xray,
   и правило в `xray.json` было мёртвым. Домены в списке этой защиты не имеют — их разбирает Xray.
4. **DNS:** клиентский :53 НЕ уходит под tproxy (raw-UDP-53 через прокси не ходит), а редиректится
   firewall'ом на dns-инбаунд Xray (:5300) → dns-аутбаунд → dns-модуль со сплитом (регион → `direct_dns`
   напрямую, остальное → DoH в туннеле). Домен VPN-сервера резолвится direct'ом (иначе bootstrap-дедлок).
   dnsmasq остаётся резолвером самого роутера.
5. **Отказоустойчивость:** watchdog (cron 1/мин) — liveness через socks + сверка exit-IP ≠ домашнего.
   3 провала → лестница восстановления (`recovery.sh`), по ступени на тик: soft bounce (`kill` xray,
   procd поднимает) → hard restart (SIGTERM → подтверждённая смерть → SIGKILL → `init.d start`,
   `apply.sh` пересобирает nft/policy-routing) → failover (`ubus config_apply {deadline}` →
   `selectWorking` выберет другой сервер, не начиная пробу, которая не успеет до дедлайна) → full stop/start (аналог ручного Off/On). На первых трёх kill-switch
   держится. Исчерпали → `init.d stop` (LAN на direct) + backoff-попытки восстановления с failover.
   Решение: `.context/decisions/2026-08-06-recovery-ladder.md`.
6. **Железо (LAN):** `eth1` = USB-адаптер RTL8153B (r8152) и единственный член `br-lan`. Пакетная
   прошивка v2 подвешивает TX-очередь (openwrt#22130) → `nicfw.sh` ставит v1 (нужна перезагрузка,
   пинится в sysupgrade.conf), `nicwatch.sh` (cron 1/мин, 2 чтения sysfs) страхует: реагирует только
   если tx_errors растёт, а tx_packets — нет; эскалация bounce → USB re-bind → backoff.
7. **Загрузка файлов:** `fetch.sh` (`mb_fetch`) — direct, при провале фолбэк через socks xray
   (`127.0.0.1:10808`). Трафик роутера идёт мимо tproxy, поэтому упирается в блокировки провайдера
   (`raw.githubusercontent.com`), из-за чего RU-сет не собирался и весь RU-трафик уходил в туннель.
   Мёртвое зеркало не обязано отказывать в соединении: gh-прокси принимают TCP и отдают ~140 байт/с,
   и `--connect-timeout` такое не ловит. Поэтому у curl есть порог скорости (`MB_FETCH_MIN_RATE` за
   окно `MB_FETCH_STALL`) — иначе перебор сжигал целый таймаут на каждом залипшем зеркале
   (установка hysteria: 8м46с против 43с после).

## Границы тестируемости
- `parser` и `generator` — чистые функции на структурах → host unit/snapshot тесты (ucode-харнесс).
- `rpcd` — хендлеры тестируются напрямую на мок-входе; ubus/uci-привязка тонкая.
- Сеть (TPROXY/DNS/kill-switch/leak) — netns-харнесс; финал на R2S.

## Ключевые решения
Полная спецификация и обоснования: `.context/specs/2026-06-05-monkey-business-vpn-client.md`.
- LuCI-оверлеи (`luci/…/monkey-business/kit/`): `layers.js` — стек слоёв (Esc / Tab на document, inert
  страницы и нижних слоёв за верхним, IME и `defaultPrevented` пропускает), `scrolllock.js` — лок
  скролла со счётчиком и компенсацией скроллбара, `trigger.js` — триггер по клику (Safari кнопки не
  фокусирует), `focusable.js` — Tab по кругу. Новый оверлей — через `layers.push` + `scrolllock.lock`,
  без своих keydown / inert. Runbook — раздел «Оверлеи» в `specs/2026-10-10-compact-ui-runbook.md`.
- Вид шторки — `kit/sheet.js` (варианты `open`: `top`, `mtop`, `foot: 'row' | 'stack'`, `compact`),
  CSS — `kit/sheetcss.js`. Вкладки приложения — `kit/tabs.js` `render(active)` первым в корне `.mb`
  каждой вьюхи; `#tabmenu` LuCI скрыт. Шапка вьюхи (h1, подзаголовок, Reset / Save / Save & Apply, на
  ≤ 720px — липкая панель снизу) — `kit/viewbar.js` `render(title, sub, actions)`, корень `.mb.mb-view`.
  Строки формы — `kit/field.js` `row()`: `hint` + `brief` (короткая подсказка на ≤ 720px). Тема bootstrap на ≤ 720px ставит инпутам 16px, кнопкам 14px
  через `!important`: инпуты оставлены 16px (iOS зумит при меньшем кегле).
