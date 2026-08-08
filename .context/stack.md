# Стек

**Домен:** systems / networking / embedded (OpenWrt firmware app).

## Целевая платформа
- **Боевое устройство: OpenWrt 25.12.1** (apk, не opkg). ImmortalWrt поддерживается, но на железе
  стоит именно OpenWrt — сверяться с ним.
- Железо: NanoPi R2S — RK3328, ARMv8 **aarch64**, 2×Ethernet, ~1 ГБ RAM, без аппаратного AES.
- **LAN = `eth1`** — USB-адаптер RTL8153B (драйвер `r8152`), единственный член `br-lan`; `eth0` = WAN.
  Пакетная прошивка `rtl8153b-2 v2` вешает TX-очередь (openwrt#22130) → держим v1 (`nicfw.sh`).
- Роль: основной шлюз LAN.

## Компоненты
- **Прокси-движок:** Xray-core (этап 3). Генератор конфига абстрагирован под будущий sing-box.
- **Второй протокол:** hysteria2 — отдельный процесс `hysteria client` (свой QUIC-стек, в xray его
  нет), локальный socks `127.0.0.1:10810`, в который смотрит аутбаунд `proxy` xray. Поднимается
  вторым procd-инстансом того же сервиса при наличии `/etc/monkey-business/hysteria.json`. Бинаря в
  feeds нет — ставится кнопкой на дашборде (`hysteria.sh install` через `mb_fetch`). Сумма
  обязательна и берётся из релизного `hashes.txt` (отдельных `<asset>.sha256` апстрим НЕ публикует),
  собирается со всех зеркал ДО скачивания 21МБ и принимается по большинству голосов, но не меньше
  двух (`hysum.sh`).
- **Backend-логика:** **ucode** (`.uc`) — парсер подписки, генератор UCI→Xray JSON, rpcd-хендлеры.
- **UI:** LuCI client-side JS (luci-base, ubus/rpcd).
- **Конфиг:** UCI `/etc/config/monkey-business` → генератор → Xray JSON.
- **Перехват трафика:** nftables TPROXY (fw4 include).
- **Direct-bypass:** nft-сеты `mb_ru4`/`mb_ru6` (`ruset.sh`) — RU-CIDR минуют TPROXY в ядре и
  проходят leak-guard. Список — текстовый CIDR-дамп Loyalsoldier/geoip (не `.dat`). Своей UCI-опции
  НЕТ: включённость производна от сплита — `routing_mode=bypass-local` + `local_region=ru`
  (`mb_direct_bypass()` в init.d — авторитет для файрвола, `directBypass()` в lib/bypass.uc — для
  UI; в status уходит ФАКТ из nft, а не намерение). Старый ключ `global.direct_bypass` удаляется
  миграцией `mb_migrate_bypass` при старте. Xray-правило `geoip:<регион> → direct` — safety-net.
- **DNS:** прозрачный через Xray (клиентский :53 → dns-инбаунд :5300 → dns-модуль со сплитом:
  регион direct / остальное DoH в туннеле). dnsmasq — резолвер самого роутера.
- **Geo:** geoip.dat/geosite.dat (скачивание при установке + кнопка обновить).
- **Отказоустойчивость:** watchdog (cron 1/мин) + failover при подключении (`selectWorking` —
  эфемерная xray-проба каждого сервера по порядку списка).

## Инструменты разработки
- **Тесты:** ucode-харнесс (`test/harness.uc`) + bash netns-харнесс.
- **Прогон на macOS:** Docker-контейнер `alpine:edge` (ucode, shellcheck). Цели — в `Makefile`.
- **Dev-среда:** QEMU aarch64 ImmortalWrt (`scripts/dev-vm.sh`); финал на R2S.
- **Сборка пакета:** OpenWrt SDK → ipk → GitHub Releases.
- **Lint:** `ucode -c`/loadfile (syntax), shellcheck, eslint (LuCI JS).

## Версии
- ucode: из alpine:edge (свежая ветка с модулями/loadfile; 3.x Alpine слишком старый).
- Xray-core: фиксируется на этапе 3.
