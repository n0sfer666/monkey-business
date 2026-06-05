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

## Начало работы

### Требования
- **Docker** (запущенный demon) — все тесты/линт гоняются в Linux-контейнере, т.к. macOS-хост
  не имеет ucode/nftables/netns.
- **qemu** (`brew install qemu`) — только для dev-VM.

### Цикл разработки (на хосте)
Код правится на хосте, проверки — в контейнере (собирается автоматически при первом запуске):
```sh
make help          # список целей
make test          # lint + ucode/js syntax + 43 unit-теста
make test-unit     # только ucode unit/snapshot
make lint          # shellcheck + ucode + js syntax
make test-integ    # netns TPROXY + валидация конфига реальным xray (privileged Docker)
```

### Dev-VM (ImmortalWrt aarch64 в QEMU)

`make dev-up` запускает VM в режиме **последовательной консоли** (`-nographic`) прямо в текущем
терминале: видны логи загрузки, затем root-shell (на свежем образе пароль не задан).

| Действие | Команда |
|----------|---------|
| Запустить VM (консоль в этом терминале) | `make dev-up` |
| Выйти из консоли QEMU (VM продолжит работать) | нажать `Ctrl-a`, затем `x` (это останавливает QEMU) |
| Зайти по SSH (из **другого** терминала) | `make dev-ssh` → `root@localhost:2222` |
| Открыть LuCI в браузере | http://localhost:8080 |
| Остановить VM | `make dev-down` |
| Удалить образ/диск | `sh scripts/dev-vm.sh clean` |

**Первый вход (важно):**
1. `make dev-up` → дождаться приглашения. На консоли ты уже root (без пароля).
2. Задать пароль для SSH/LuCI — на консоли VM:
   ```sh
   passwd          # без пароля dropbear/LuCI не пустят
   ```
3. Теперь из другого терминала: `make dev-ssh` (или открыть http://localhost:8080).

> Сеть VM — QEMU user-mode NAT (один интерфейс): есть исходящий интернет, проброшены
> `:2222→22` и `:8080→80`. Этого хватает для разработки UI/логики и `opkg`. Полный сценарий
> «LAN-клиент через TPROXY» проверяется в netns (`make test-integ`), а не в этой VM.

Переменные: `MB_VM_SSH_PORT` (2222), `MB_VM_HTTP_PORT` (8080), `MB_VM_MEM` (512),
`MB_IMMORTALWRT_URL` (URL образа).

### Деплой кода в VM для экспериментов
После того как на VM задан пароль root:
```sh
# 1) поставить рантайм-зависимости (один раз, на консоли/по ssh в VM):
opkg update
opkg install ucode ucode-mod-uci ucode-mod-fs xray-core kmod-nft-tproxy luci-base

# 2) с хоста — разложить файлы проекта по реальным путям и перезапустить rpcd:
make dev-deploy

# 3) проверить, что ubus-объект поднялся (в VM):
ubus call monkey-business status
```
`make dev-deploy` копирует `src/`, `root/`, `luci/`, `scripts/firewall/` в нужные места
(`/usr/share/rpcd/ucode/...`, `/etc/config`, `/etc/init.d`, `/www/luci-static/...`) и делает
`rpcd restart`. После деплоя раздел появится в LuCI: **Services → monkey-business VPN**.

### Где что устанавливается
| Исходник | Путь в системе |
|----------|----------------|
| `root/usr/share/rpcd/ucode/monkey-business.uc` | rpcd-плагин (ubus-объект) |
| `src/*` | `/usr/share/rpcd/ucode/lib/monkey-business/` (импорты плагина) |
| `root/etc/config/monkey-business` | UCI-конфиг |
| `root/etc/init.d/monkey-business` | procd init (запуск xray) |
| `scripts/firewall/*.sh` | `/usr/share/monkey-business/firewall/` |
| `luci/htdocs/.../view/monkey-business/*.js` | `/www/luci-static/resources/view/monkey-business/` |
| `luci/root/.../menu.d`, `acl.d` | меню и ACL LuCI |

## Статус
Backend (парсер/генератор/rpcd) — ucode, покрыт **43 host-тестами**. Сетевая часть — netns-харнесс
(`make test-integ`: реальный TPROXY-перехват + валидация конфига настоящим xray). Реальное
подключение к VPNON, прошивка R2S и перф-тесты — на железе. Подробности: `.claude/reports/`.

## Лицензия
TBD.
