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

VM запускается **фоном** (headless). Консоль — на unix-сокете, не занимает терминал.
Вход: SSH или браузер. **Логин/пароль: `root` / `root`** (задаётся автонастройкой).

> ⚠️ Не используй `Ctrl-a x` — это **убивает** QEMU. Останавливать VM только через `make dev-down`.

#### Быстрый старт (копипаст, по порядку)
```sh
brew install qemu        # один раз, если ещё нет
make dev-up              # 1. скачать образ и запустить VM (фоном, ~1-2 мин)
make dev-provision       # 2. автонастройка: сеть(DHCP)+пароль root/root+установка LuCI (~3 мин, ОДИН раз)
```
После этого:
- **LuCI в браузере:** http://localhost:8080 — логин `root`, пароль `root`
- **SSH:** `make dev-ssh` — пароль `root`

`make dev-provision` нужен только при первом запуске (или после `make dev-... clean`):
он чинит сеть (гость берёт DHCP → работают проброс портов и интернет), ставит пароль
`root/root` и устанавливает LuCI+uhttpd. Всё это сохраняется на диске — дальше хватает `make dev-up`.

#### Команды dev-VM
| Команда | Что делает |
|---------|-----------|
| `make dev-up` | запустить VM фоном (скачает образ при первом запуске) |
| `make dev-provision` | автонастройка (сеть/пароль/LuCI) — один раз |
| `make dev-ssh` | SSH в VM (`root`/`root`) |
| `make dev-console` | подключиться к консоли VM (выход `Ctrl-C`, VM продолжит работать) |
| `make dev-status` | статус VM и порты |
| `make dev-deploy` | разложить проект по путям в VM + restart rpcd |
| `make dev-down` | остановить VM |
| `sh scripts/dev-vm.sh clean` | удалить образ/диск (полный сброс) |

> Сеть VM — QEMU user-mode NAT (один интерфейс): исходящий интернет + проброс `:2222→22`, `:8080→80`.
> Хватает для разработки UI/логики и `apk`. Сценарий «LAN-клиент через TPROXY» проверяется в
> netns (`make test-integ`), а не в этой VM. Переменные: `MB_VM_SSH_PORT`, `MB_VM_HTTP_PORT`, `MB_VM_MEM`.

> Пакетный менеджер в свежем ImmortalWrt — **`apk`** (не `opkg`).

### Деплой кода в VM для экспериментов
```sh
# 1) рантайм-зависимости в VM (один раз). Можно по SSH или через консоль:
make dev-ssh
#   ↳ внутри VM:
apk update
apk add ucode-mod-uci ucode-mod-fs xray-core kmod-nft-tproxy
exit

# 2) с ХОСТА — разложить файлы проекта и перезапустить rpcd (спросит пароль root = root):
make dev-deploy

# 3) проверить, что ubus-объект поднялся (по SSH в VM):
make dev-ssh
#   ↳ внутри VM:
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
