# Стек

**Домен:** systems / networking / embedded (OpenWrt firmware app).

## Целевая платформа
- ImmortalWrt (приоритет) + совместимость OpenWrt.
- Железо: NanoPi R2S — RK3328, ARMv8 **aarch64**, 2×Ethernet, ~1 ГБ RAM, без аппаратного AES.
- Роль: основной шлюз LAN.

## Компоненты
- **Прокси-движок:** Xray-core (этап 3). Генератор конфига абстрагирован под будущий sing-box.
- **Backend-логика:** **ucode** (`.uc`) — парсер подписки, генератор UCI→Xray JSON, rpcd-хендлеры.
- **UI:** LuCI client-side JS (luci-base, ubus/rpcd).
- **Конфиг:** UCI `/etc/config/monkey-business` → генератор → Xray JSON.
- **Перехват трафика:** nftables TPROXY (fw4 include).
- **DNS:** прозрачный через Xray (клиентский :53 → dns-инбаунд :5300 → dns-модуль со сплитом:
  регион direct / остальное DoH в туннеле). dnsmasq — резолвер самого роутера.
- **Geo:** geoip.dat/geosite.dat (скачивание при установке + кнопка обновить).

## Инструменты разработки
- **Тесты:** ucode-харнесс (`test/harness.uc`) + bash netns-харнесс.
- **Прогон на macOS:** Docker-контейнер `alpine:edge` (ucode, shellcheck). Цели — в `Makefile`.
- **Dev-среда:** QEMU aarch64 ImmortalWrt (`scripts/dev-vm.sh`); финал на R2S.
- **Сборка пакета:** OpenWrt SDK → ipk → GitHub Releases.
- **Lint:** `ucode -c`/loadfile (syntax), shellcheck, eslint (LuCI JS).

## Версии
- ucode: из alpine:edge (свежая ветка с модулями/loadfile; 3.x Alpine слишком старый).
- Xray-core: фиксируется на этапе 3.
