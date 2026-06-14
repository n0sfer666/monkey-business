# monkey-business

[English](README.md) | **Русский**

Минималистичный VPN-клиент для роутеров на **OpenWrt / ImmortalWrt** (целевое железо — **NanoPi R2S**).
Reality + VLESS + XHTTP с простым интерфейсом на LuCI — лёгкая альтернатива passwall / v2rayA.

```
LuCI (JS) → rpcd (ucode) → UCI → генератор конфига → Xray-core + nftables TPROXY + dnsmasq
```

Импорт подписки (формат определяется автоматически) или ручное добавление `vless://`-серверов;
сплит-маршрутизация по geoip/geosite (локальный регион — напрямую, остальное — через туннель),
kill-switch, блокировка утечки IPv6, split-DNS поверх DoH, anti-DPI (uTLS + XHTTP-паддинг) и
дашборд на одном экране.

> ⚠️ **В разработке.** Бэкенд (парсер подписки, генератор конфига, rpcd-хендлеры) покрыт
> host-юнит-тестами; сетевой путь (TPROXY/DNS) — netns-харнессом и валидацией конфига реальным
> `xray`. Реальная пропускная способность VPN проверяется на железе.

---

## Установка

Приложение работает на роутере. Два способа доставить его туда.

### Вариант A — деплой по SSH (без сборки пакета)

Если ImmortalWrt/OpenWrt уже стоит на роутере и есть SSH-доступ, разложите файлы напрямую:

```sh
MB_VM_SSH_HOST=root@<router-ip> MB_VM_SSH_PORT=22 MB_VM_SSH_PASS=<password> \
  sh scripts/deploy-vm.sh
```

```nu
# nushell
with-env { MB_VM_SSH_HOST: "root@<router-ip>", MB_VM_SSH_PORT: "22", MB_VM_SSH_PASS: "<password>" } { sh scripts/deploy-vm.sh }
```

Это устанавливает rpcd-плагин, LuCI-вьюшки, init-скрипт, firewall- и geo-скрипты и идемпотентно
подтягивает рантайм-зависимости (`xray-core`, `kmod-nft-tproxy`, `curl`, модули rpcd/ucode) через
`apk`. Затем откройте LuCI → **Services → monkey-business VPN**.

Пошаговое руководство для NanoPi R2S (зависимости, geo-базы, первое подключение, проверка) —
в **[docs/install-nanopi.ru.md](docs/install-nanopi.ru.md)**.

### Вариант B — сборка `.ipk`

Сборка пакета через OpenWrt/ImmortalWrt SDK под целевую платформу (rockchip/armv8):

```sh
export MB_SDK_DIR=/path/to/immortalwrt-sdk   # SDK под rockchip/armv8
make package
```

```nu
# nushell
$env.MB_SDK_DIR = "/path/to/immortalwrt-sdk"  # SDK под rockchip/armv8
make package
```

Артефакт появится в `bin/packages/aarch64*/` внутри SDK; скопируйте его на роутер и выполните
`apk add ./<pkg>.ipk` (или `opkg install`). *(Сборка через SDK ещё допиливается — см.
`scripts/package.sh`; пока используйте Вариант A.)*

### Первый запуск

1. Вкладка **Servers** — вставьте URL подписки и нажмите *Fetch*, либо добавьте `vless://`-сервер вручную.
2. **Dashboard** — *Update geo databases* (скачивает и валидирует geoip/geosite `.dat`).
3. **Dashboard** — *Turn on*. *Check exit IP* подтверждает, что трафик уходит через туннель.

---

## Разработка

Код правится на хосте; проверки выполняются в Linux-контейнере (собирается автоматически при
первом запуске), потому что на macOS-хосте нет ucode/nftables/netns.

```sh
make test        # линт (shellcheck + ucode syntax + eslint) + ucode unit/snapshot-тесты
make test-integ  # netns TPROXY-перехват + сгенерированный конфиг, проверенный реальным xray
```

Структура:

| Путь | Что |
|------|------|
| `src/parser/` | парсер подписки (base64 / uri-list; авто-определение формата) |
| `src/generator/` | генератор UCI → Xray JSON (абстрагирован под будущий бэкенд sing-box) |
| `src/rpcd/` | чистые rpcd-хендлеры (host-тестируемые; привязка ubus/uci в `root/…/rpcd/ucode`) |
| `src/lib/` | общие утилиты (разбор URI) |
| `luci/` | LuCI client-side JS-вьюшки (dashboard / servers / settings) + меню + ACL |
| `root/` | файлы на устройстве: UCI-дефолты, procd-init, рантайм rpcd-плагин, geo-скрипт |
| `scripts/firewall/` | nftables TPROXY apply/flush |
| `test/` | ucode-харнесс + unit/snapshot-тесты + netns-интеграция |

Чистая логика (`parser`, `generator`) не зависит от `uci`/`ubus`, поэтому host-тестируема;
device-привязан только рантайм rpcd-плагин и shell-скрипты. Полная архитектура, конвенции и
спеки — в `.context/`.

### Предпросмотр на живом роутере (dev-VM)

Посмотреть приложение на реальной системе ImmortalWrt aarch64 в QEMU до прошивки железа:

```sh
make dev-up         # запустить VM headless (при первом запуске скачивает образ)
make dev-provision  # один раз: DHCP + пароль root + LuCI (~несколько минут)
make dev-deploy     # установить приложение в VM и перезагрузить rpcd
make dev-test-split # проверить сплит-маршрутизацию: выходной IP/страна через тестовый SOCKS-inbound
```

Затем откройте **http://localhost:8090** (логин `root` / `root`) → **Services → monkey-business VPN**.
Переопределите порт через `MB_VM_HTTP_PORT=NNNN make dev-up`, если 8090 занят
(nushell: `with-env { MB_VM_HTTP_PORT: "NNNN" } { make dev-up }`).

| Команда | Назначение |
|---------|------------|
| `make dev-up` | запустить VM (в фоне, headless) |
| `make dev-provision` | разовая настройка (сеть / пароль / LuCI) |
| `make dev-deploy` | деплой приложения + рантайм-deps, перезагрузка rpcd |
| `make dev-ssh` | SSH в VM (`root` / `root`) |
| `make dev-rebuild` | полная чистая пересборка VM (если зависает загрузка) |
| `make dev-down` | остановить VM |

> VM использует QEMU user-mode NAT (SSH `:2222→22`, LuCI `:8090→80`) — этого хватает для работы
> с UI/логикой. Сценарий «LAN-клиент через TPROXY» отрабатывается `make test-integ`, а не этой VM.

---

## Решение проблем

### Dev-VM (QEMU)

На Apple Silicon VM использует **HVF** (почти нативно); на других платформах — медленную TCG-эмуляцию.

- **Загрузка виснет на `procd: - ubus -` (SSH-таймаут «banner exchange») — при reboot ИЛИ при втором
  `dev-up` уже использованного диска.**
  Гонка QEMU-эмуляции, при которой `ubusd` не поднимается на любой *не-первой* загрузке
  (openwrt/openwrt#9492, #13600) — **не** приложение и не лечится HVF/virtio-rng. Надёжна только
  первая загрузка свежескачанного образа. Восстановление — одна команда:
  ```sh
  make dev-rebuild   # clean + up + provision + deploy с нуля (~5–8 мин)
  ```
  Чтобы избежать: **держите VM запущенной между сессиями** (не делайте `make dev-down`) и никогда не
  делайте `reboot` гостя — используйте `make dev-down` / `dev-up`. На реальном NanoPi R2S этой гонки нет.

- **Объект ubus не регистрируется / `Failed to connect to ubus` после `make dev-deploy`.**
  Обрабатывается текущими скриптами; если столкнулись — исторически было две причины:
  1. **rpcd компилирует ucode-плагины из буфера** (без пути к файлу), поэтому точка входа rpcd
     должна использовать **абсолютный** путь импорта. Относительные `./…`-импорты падают под rpcd
     (но работают через CLI `ucode`, что прячет баг). Транзитивно импортируемые модули `lib/` могут
     оставаться относительными.
  2. **Эмулируемый `ubusd` виснет на `rpcd restart`** (жив, но перестаёт принимать соединения,
     openwrt#9492). `make dev-deploy` это детектит и **пересоздаёт `ubusd`+`rpcd` свежими** (только
     dev-VM, через `MB_UBUS_RESPAWN=1`; никогда на реальном железе).
  Также macOS `tar` добавляет AppleDouble-файлы `._*` — деплой их вычищает (`COPYFILE_DISABLE=1`);
  иначе они дошли бы и до реального R2S. Проверка на цели:
  `cat /usr/share/rpcd/ucode/monkey-business.uc | ucode -R -` (должно завершиться без ошибок), затем
  `ubus call monkey-business status`.

- **Нет интернета в VM / `apk` падает / LuCI не установился.** Гость должен быть на `10.0.2.15`
  (QEMU SLIRP). `make dev-provision` ставит это статически; проверьте через `make dev-ssh`, затем
  `ip -4 addr show br-lan`. Если показывает `192.168.1.1` — перезапустите `make dev-provision`.

Для бэкенда (ubus/rpcd/ucode/xray) самая надёжная цель — реальное железо: `deploy-vm.sh` умеет
целиться в NanoPi R2S по SSH (см. Установка → Вариант A).

### Рантайм (на роутере)

- **`Turn on` падает / `geo databases missing`.** Xray не стартует без geoip/geosite `.dat`.
  Сначала нажмите **Update geo databases** на дашборде (качает ~30 МБ в фоне и валидирует через
  `xray -test` перед установкой — дольше ubus-таймаута, поэтому это отдельная кнопка).
- **`no servers — add a subscription or a manual server first`.** Импортируйте подписку на вкладке
  Servers или добавьте `vless://`-сервер вручную.
- **Apply падает с сообщением Xray.** Сгенерированный конфиг валидируется через `xray -test` перед
  записью; показывается первая строка ошибки. Частая причина — неверные Reality SNI/publicKey/shortId
  в записи сервера.
- **Статус застрял на «Starting…».** Xray запустился, но не работает — вероятно, упал. Смотрите
  `logread | grep xray`. (Проверка живости через `pidof xray`; BusyBox `pgrep -x` не матчит.)
- **«Check exit IP» возвращает ошибку.** Проба идёт через тестовый SOCKS-inbound — убедитесь, что
  VPN включён и сервис запущен.
- **Изменения настроек/маршрутизации не применяются из LuCI.** Save & Apply коммитит на стороне
  сервера (`config_apply` / `set_routing`), чтобы ничего не оставалось в «Unsaved Changes» LuCI.

---

## Обратная связь

Нашли баг, наткнулись на пограничный кейс маршрутизации или хотите фичу? Используйте GitHub:

- **Баги / запросы фич** → [откройте issue](https://github.com/n0sfer666/monkey-business/issues).
  Укажите модель роутера, версию ImmortalWrt/OpenWrt, режим маршрутизации и локальный регион, а также
  релевантный вывод `logread | grep -iE 'xray|monkey-business'` (замаскируйте токен подписки/UUID).
- **Вопросы / идеи** → [GitHub Discussions](https://github.com/n0sfer666/monkey-business/discussions).
- **Патчи** → pull request'ы приветствуются. Перед отправкой запустите `make test` (и `make test-integ`,
  если трогали генератор или firewall); держите коммиты в стиле
  [Conventional Commits](https://www.conventionalcommits.org).

---

## Лицензия

[GPL-3.0](LICENSE).
