# monkey-business

[English](README.md) | **Русский**

Минималистичный VPN-клиент для роутеров на **OpenWrt / ImmortalWrt** (целевое железо — **NanoPi R2S**).
Reality + VLESS + XHTTP (и hysteria2) с простым интерфейсом на LuCI — лёгкая альтернатива
passwall / v2rayA.

```
LuCI (JS) → rpcd (ucode) → UCI → генератор конфига → Xray-core + nftables TPROXY + dnsmasq
```

Импорт подписки (формат определяется автоматически) или ручное добавление `vless://`- и
`hysteria2://`-серверов; сплит-маршрутизация по geoip/geosite (локальный регион — напрямую,
остальное — через туннель), kill-switch, блокировка утечки IPv6, split-DNS поверх DoH, anti-DPI
(uTLS + XHTTP-паддинг) и дашборд на одном экране.

Оба протокола живут в **одном** списке серверов: протокол — свойство сервера, поэтому порядок
списка остаётся единственным приоритетом, а failover перебирает кандидатов сквозь протоколы.
hysteria2 работает отдельным клиентом рядом с Xray (аутбаунд `proxy` превращается в локальный
socks), так что сплит, DNS и kill-switch — ровно те же, что у VLESS. Бинарь клиента ставится
кнопкой на дашборде.

Две вещи происходят без вашего участия. **Трафик локального региона минует прокси прямо в ядре**:
его CIDR-диапазоны лежат в nftables-сетах (`mb_ru4`/`mb_ru6`), исключённых из TPROXY, поэтому он не
платит за лишний хоп через Xray — а правило `geoip:<регион> → direct` внутри Xray остаётся
подстраховкой. И **упавший туннель чинит себя сам**: cron-watchdog раз в минуту пробит туннель и
идёт по лестнице — *мягкий bounce → жёсткий рестарт → переключение на следующий рабочий сервер →
полный цикл stop/start → откат на direct*, вместо того чтобы оставить LAN за fail-closed
kill-switch'ем. Такая же проба выбирает сервер при подключении:
кандидаты перебираются по порядку списка, побеждает первый, через который реально идёт трафик.

> ⚠️ **В разработке.** Бэкенд (парсер подписки, генератор конфига, rpcd-хендлеры) покрыт
> host-юнит-тестами; сетевой путь (TPROXY/DNS) — netns-харнессом и валидацией конфига реальным
> `xray`. Реальная пропускная способность VPN проверяется на железе.

---

## Установка

Приложение работает на роутере. Два способа доставить его туда.

### Вариант A — деплой по SSH (без сборки пакета)

Если ImmortalWrt/OpenWrt уже стоит на роутере и есть SSH-доступ, команда в одну строку —
`make deploy`: обёртка (`scripts/deploy.sh`), которая сначала гонит локальные проверки, затем
деплоит с device-дефолтами (SSH :22) и сохраняет ваш `/etc/config/monkey-business` между запусками:

```sh
make deploy HOST=root@<router-ip>          # добавьте MB_PASS=… если без SSH-ключа
```

Под капотом вызывается `scripts/deploy-vm.sh` — его можно запустить и напрямую:

```sh
MB_VM_SSH_HOST=root@<router-ip> MB_VM_SSH_PORT=22 MB_VM_SSH_PASS=<password> \
  sh scripts/deploy-vm.sh
```

```nu
# nushell
with-env { MB_VM_SSH_HOST: "root@<router-ip>", MB_VM_SSH_PORT: "22", MB_VM_SSH_PASS: "<password>" } { sh scripts/deploy-vm.sh }
```

**По SSH-ключу** (рекомендуется) — авторизуйте его один раз (`ssh-copy-id root@<router-ip>`), затем
просто опустите `MB_VM_SSH_PASS`; ключ/ssh-agent подхватятся автоматически:

```sh
MB_VM_SSH_HOST=root@<router-ip> MB_VM_SSH_PORT=22 sh scripts/deploy-vm.sh
```

```nu
# nushell
with-env { MB_VM_SSH_HOST: "root@<router-ip>", MB_VM_SSH_PORT: "22" } { sh scripts/deploy-vm.sh }
```

`<router-ip>` — LAN-адрес роутера, обычно `192.168.1.1` (приватный диапазон `192.168.x.x`).

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

1. Вкладка **Servers** — вставьте URL подписки и нажмите *Fetch*, либо добавьте `vless://`- или
   `hysteria2://`-сервер вручную.
2. **Dashboard** — *Update geo databases* (скачивает и валидирует geoip/geosite `.dat`).
3. **Dashboard** — *Install / update hysteria* — только если в списке есть hysteria2-серверы.
4. **Dashboard** — *Turn on*. *Check exit IP* подтверждает, что трафик уходит через туннель.

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
| `src/parser/` | парсер подписки (base64 / uri-list; авто-определение формата; `vless://` + `hysteria2://`) |
| `src/generator/` | генератор UCI → Xray JSON (абстрагирован под будущий бэкенд sing-box) + конфиг hysteria-клиента |
| `src/rpcd/` | чистые rpcd-хендлеры (host-тестируемые; привязка ubus/uci в `root/…/rpcd/ucode`) |
| `src/runtime/` | device-привязанная обвязка, вынесенная из rpcd-плагина (конфиг/установка/проба hysteria) |
| `src/lib/` | общие утилиты (разбор URI) |
| `luci/` | LuCI client-side JS-вьюшки (dashboard / servers / settings) + панель сплита (`routing.js`, рендерится внутри дашборда) + меню + ACL |
| `root/` | файлы на устройстве: UCI-дефолты, procd-init, рантайм rpcd-плагин |
| `root/usr/share/monkey-business/` | shell на устройстве: `watchdog.sh` + `probes.sh` + `recovery.sh` + `phases.sh` (самовосстановление), `ruset.sh` (nft-сеты direct-bypass), `geo.sh`, `fetch.sh` (общая загрузка, socks-фолбэк), `boothealth.sh`, `hysteria.sh` (установщик клиента hysteria2), `subupdate.sh` (автообновление подписки по расписанию), `nicfw.sh` + `nicwatch.sh` (USB-сетевуха RTL8153B, см. [гайд §9](docs/install-nanopi.ru.md#9-usb-сетевуха-rtl8153b-прошивка-и-watchdog)) |
| `scripts/firewall/` | nftables TPROXY apply/flush |
| `scripts/expand-sd.sh` | расширение ext4-раздела SD-карты с macOS ([док](docs/sd-expand-macos.ru.md)) |
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
- **LAN-клиент пингует IP локального региона, но не зарубежные.** Так и задумано — при включённом
  kill-switch (дефолт). ICMP никогда не проксируется (перехватывается только TCP/UDP), поэтому
  зарубежный IP дропается kill-switch'ем, а IP локального региона проходит, потому что лежит в
  bypass-сетах `mb_ru4`/`mb_ru6`. То есть ping показывает членство в сете, а не здоровье туннеля —
  проверяйте через `nft list set inet monkey_business mb_ru4`.
- **Bypass-сеты пустые / локальный трафик всё равно идёт через Xray.** CIDR-список собирается на
  этапе деплоя; пересоберите вручную — `sh /usr/share/monkey-business/ruset.sh build` (cron-задания
  нет, а кнопка *Update geo databases* его **не** пересобирает — она обновляет только `.dat`-файлы).
  Пустой сет — это не утечка: правило Xray `geoip:<регион> → direct` всё равно уведёт такой трафик
  напрямую, просто медленнее. Своего тумблера у механизма нет: он производный от сплита на
  дашборде и включён только при **Bypass local + Russia** (сеты наполняются RU-списком CIDR, так что
  в любом другом режиме или регионе он уводил бы мимо туннеля трафик, который вы просили в туннель).
  Чтобы выключить — выберите другой режим маршрутизации; дашборд показывает, что включает каждый выбор.
- **Туннель упал, и роутер сам переключил сервер.** Это watchdog. Он пишет только переходы, в
  syslog — `logread -f -e mb-event` покажет `Reconnecting…` /
  `VPN recovered by <ступень>…` / `VPN stopped, LAN on direct`. Текущее состояние —
  в `/tmp/mb-watchdog/state`. Лестница эскалации, тюнинг и отключение — в
  [руководстве по установке](docs/install-nanopi.ru.md#8-самовосстановление-watchdog-и-failover).
- **Direct-сайты (мимо туннеля) тормозят при живом туннеле.** Обычно это `odhcp6c` в busy-loop на
  `wan6`, когда провайдер не выдаёт IPv6 — см.
  [руководство по установке](docs/install-nanopi.ru.md#7-заметки-по-nanopi-r2s-и-решение-проблем).

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
