# monkey-business

VPN-клиент **Reality + VLESS + XHTTP** для ImmortalWrt/OpenWrt (целевое железо — NanoPi R2S).
Аналог passwall/v2rayA с минималистичным интерфейсом и современными технологиями обхода блокировок.

> ⚠️ В разработке. См. план: `.claude/plans/2026-06-05-monkey-business.md`
> и спецификацию: `.context/specs/2026-06-05-monkey-business-vpn-client.md`.

## Возможности (целевые)
- Подписка VPNON + ручное добавление серверов (VLESS/Reality/XHTTP).
- Маршрутизация по geoip/geosite: bypass RU/CN → остальное через VPN.
- TPROXY-перехват (nftables/fw4), kill-switch (fail-closed), блок IPv6-утечек.
- Split-DNS (RU direct / DoH в туннеле), anti-DPI (uTLS + XHTTP padding).
- Минималистичный LuCI-интерфейс (RU/EN) с подсказками к каждой опции.

## Архитектура
LuCI (JS) → rpcd (ucode) → UCI → генератор → Xray-core + nftables TPROXY + dnsmasq.
Подробнее: `.context/architecture.md`.

## Разработка
```sh
make help          # список целей
make test          # lint + syntax + unit (в Docker-контейнере)
make test-unit     # ucode unit/snapshot тесты
make lint          # shellcheck + ucode syntax
make dev-up        # dev-VM в QEMU (нужен qemu-system-aarch64)
```
Проверки гоняются в Linux-контейнере (`Dockerfile.test`), т.к. ucode/nftables/netns — Linux-only.

## Статус
Backend (парсер/генератор/rpcd) — ucode, покрыт host-тестами. Сетевая часть — netns-харнесс.
Реальное подключение к VPNON, прошивка R2S и перф-тесты — на железе пользователя.

## Лицензия
TBD.
