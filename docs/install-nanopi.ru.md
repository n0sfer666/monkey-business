# Установка monkey-business на NanoPi R2S

[English](install-nanopi.md) | **Русский**

Подробное пошаговое руководство по запуску VPN-клиента на **NanoPi R2S** (RK3328, aarch64), на
котором **уже работает ImmortalWrt/OpenWrt** и доступен SSH.

Если ImmortalWrt ещё нужно прошить на SD-карту и поднять сеть — сделайте это сначала
(см. документацию ImmortalWrt для `rockchip/armv8` / NanoPi R2S) и вернитесь сюда.

> Везде далее `<router-ip>` — это LAN-адрес вашего R2S (дефолт ImmortalWrt/OpenWrt обычно
> `192.168.1.1`), а команды с префиксом `#` выполняются **на роутере** (через `ssh root@<router-ip>`),
> остальные — на вашей dev-машине в каталоге репозитория.

---

## 0. Предусловия и проверки

На роутере подтвердите платформу и свободное место — geo-базам нужно ~30 МБ, Xray ~25 МБ:

```sh
# uname -m            # ожидаем: aarch64
# cat /etc/openwrt_release | grep -E 'ARCH|RELEASE'
# df -h /             # нужно ~80–100 МБ свободно под xray-core + geo .dat
# nft --version       # fw4/nftables присутствует (в современном ImmortalWrt есть)
```

Если overlay впритык — geo `.dat` качаются в рантайме (не зашиты в пакет), поэтому сам пакет
небольшой, но xray-core + два `.dat` — основная часть объёма.

---

## 1. Установка рантайм-зависимостей

Приложению нужны эти пакеты на роутере:

| Пакет | Зачем |
|-------|-------|
| `xray-core` | прокси-движок |
| `kmod-nft-tproxy` | поддержка TPROXY в nftables (fw4) |
| `rpcd-mod-ucode` | запускает ucode rpcd-плагин |
| `ucode-mod-uci`, `ucode-mod-fs` | доступ к UCI + файловой системе из ucode |
| `curl` | загрузка подписки (захватывает заголовок трафика `Subscription-Userinfo`) |

`scripts/deploy-vm.sh` ставит их автоматически (Раздел 2). Вручную:

```sh
# apk update
# apk add xray-core kmod-nft-tproxy rpcd-mod-ucode ucode-mod-uci ucode-mod-fs curl
```

(На старых сборках с opkg используйте `opkg update && opkg install …`.)

---

## 2. Деплой файлов приложения

**Рекомендуется: `make deploy`.** Из каталога репозитория:

```sh
make deploy HOST=root@<router-ip>
```

`make deploy` — тонкая обёртка (`scripts/deploy.sh`) над dev-деплоером. Нужна, чтобы заливка на
боевое железо была безопасной и в одну строку: сначала гонит локальные проверки
(`make lint check test-unit`), чтобы не отправить сломанное, затем задаёт device-дефолты
(SSH-порт 22) и передаёт управление `scripts/deploy-vm.sh` для самой заливки. Повторный запуск —
это **обновление**: файлы перетираются, а ваш `/etc/config/monkey-business` (серверы, выбор,
настройки) сохраняется. Опциональные env-оверрайды (префиксом к команде, напр.
`MB_PASS=secret make deploy HOST=…`): `MB_PORT` (SSH-порт), `MB_PASS` (root-пароль, если без
ключа), `MB_SKIP_CHECKS=1` (пропустить проверки, если нет Docker).

Под капотом вызывается `scripts/deploy-vm.sh` — его можно запустить и напрямую для тонкого
контроля (именно его и выполняет `make deploy`):

```sh
MB_VM_SSH_HOST=root@<router-ip> \
MB_VM_SSH_PORT=22 \
MB_VM_SSH_PASS=<root-password> \
  sh scripts/deploy-vm.sh
```

```nu
# nushell
with-env {
  MB_VM_SSH_HOST: "root@<router-ip>",
  MB_VM_SSH_PORT: "22",
  MB_VM_SSH_PASS: "<root-password>"
} { sh scripts/deploy-vm.sh }
```

**По SSH-ключу** (рекомендуется) — авторизуйте его один раз (`ssh-copy-id root@<router-ip>`), затем
полностью опустите `MB_VM_SSH_PASS`; скрипт использует обычные `ssh`/`scp`, поэтому ключ/ssh-agent
подхватываются сами (никакого доп. флага не нужно):

```sh
MB_VM_SSH_HOST=root@<router-ip> MB_VM_SSH_PORT=22 sh scripts/deploy-vm.sh
```

```nu
# nushell
with-env { MB_VM_SSH_HOST: "root@<router-ip>", MB_VM_SSH_PORT: "22" } { sh scripts/deploy-vm.sh }
```

`<router-ip>` — LAN-адрес роутера, обычно `192.168.1.1` (приватный `192.168.x.x`). Проверьте его:
`191.168.x.x` — это *публичный* интернет-адрес, а не ваша сеть, и даст
`Connection closed … / lost connection`.

Что это делает:

- Готовит файлы и копирует их по нужным путям:
  - rpcd-плагин → `/usr/share/rpcd/ucode/monkey-business.uc` (+ `lib/monkey-business/` из `src/`),
  - LuCI-вьюшки → `/www/luci-static/resources/view/monkey-business/`, меню + ACL,
  - `/etc/config/monkey-business` (UCI), `/etc/init.d/monkey-business` (procd),
  - firewall-скрипты → `/usr/share/monkey-business/firewall/`, geo-скрипт → `/usr/share/monkey-business/geo.sh`.
- **Сохраняет ваш существующий `/etc/config/monkey-business`** при повторных деплоях (как conffile).
- Доставляет недостающие рантайм-зависимости через `apk` (идемпотентно).
- Перезапускает `rpcd` и проверяет регистрацию ubus-объекта:
  `>> OK: ubus-объект monkey-business зарегистрирован`.

> **Не ставьте `MB_UBUS_RESPAWN=1` для реального железа.** Этот флаг (используется только
> `make dev-deploy` для QEMU dev-VM) принудительно пересоздаёт `ubusd`/`rpcd` для обхода бага
> эмулятора. R2S это не нужно, и убивать `ubusd` на живом роутере не стоит.

> **Деплой с macOS:** `deploy-vm.sh` уже вычищает AppleDouble-файлы `._*` (`COPYFILE_DISABLE=1`).
> Если когда-нибудь копируете файлы на роутер иначе — убедитесь, что под `/usr/share/rpcd/ucode/`
> не попадают `._*`: rpcd-mod-ucode пытается их скомпилировать и падает.

Предпочтительнее ключевой SSH вместо пароля (`ssh-copy-id root@<router-ip>`), тогда опустите
`MB_VM_SSH_PASS`.

Проверьте, что бэкенд поднялся:

```sh
# ubus call monkey-business status
# ucode -R - < /usr/share/rpcd/ucode/monkey-business.uc   # должно завершиться чисто (проверка синтаксиса)
```

### Альтернатива: установка `.ipk`

Если вы собрали пакет (`make package` с SDK в `MB_SDK_DIR` — ещё допиливается), скопируйте его
на роутер и установите:

```sh
# apk add ./monkey-business_*.ipk        # или: opkg install ./monkey-business_*.ipk
```

---

## 3. Загрузка geo-баз

Xray не стартует без `geoip.dat` и `geosite.dat`. Проще всего из LuCI:

**LuCI → Services → monkey-business VPN → Dashboard → Update geo databases.**

Качает из Loyalsoldier/v2ray-rules-dat (или ваших кастомных URL), валидирует каждый файл реальным
`xray -test` и устанавливает в `/usr/share/xray/`. Загрузка (~30 МБ) идёт в фоне, а UI опрашивает
статус до завершения.

Из шелла вместо этого:

```sh
# sh /usr/share/monkey-business/geo.sh download
# ls -la /usr/share/xray/geoip.dat /usr/share/xray/geosite.dat
```

---

## 4. Добавление серверов

В **LuCI → … → Servers**:

- **Подписка:** вставьте URL провайдера и нажмите *Fetch*. Серверы импортируются (формат
  определяется автоматически: base64-список или список `vless://`-URI). Порядок списка — это ваш
  приоритет; перетаскивайте для сортировки, первый сервер — активный. Re-fetch сохраняет ваш ручной порядок.
- **Вручную:** добавьте `vless://…`-сервер (Reality/VLESS/XHTTP).

Токен подписки и UUID серверов хранятся в UCI (только root) и маскируются в UI — держите их вне
логов и issue.

---

## 5. Настройка маршрутизации (Settings)

**LuCI → … → Settings.** Разумные дефолты уже заполнены:

- **Routing mode** — `Bypass local (recommended)`: ваш локальный регион (RU/CN/IR) и приватные
  адреса идут напрямую, всё остальное — через туннель. Другие режимы: `Only blocked via VPN`
  (gfwlist) и `Everything via VPN` (global).
- **Local region** — какой регион считается «локальным» для прямой маршрутизации. Выберите
  **`Other`**, если для вашего региона нет geo-пресета: предопределённой локальной geo-категории
  нет, поэтому сплитом вы управляете сами через custom-списки **Direct (bypass VPN)** / **Via VPN**
  на дашборде. Приватные адреса остаются direct, а всё, что не попало в списки, идёт по умолчанию
  **Routing mode** (bypass-local → туннель, gfwlist → напрямую, global → туннель).
- **Kill-switch** — fail-closed (по умолчанию включён): LAN-трафик к не-локальным назначениям
  дропается, а не утекает напрямую, когда он не несётся туннелем (Xray упал, дыра в правилах или
  не-проксируемый трафик вроде ICMP). Отключите для прямого фолбэка при упавшем туннеле (менее
  безопасно). Локально-региональный и приватный трафик не затрагивается. Реализовано как nftables
  `forward` leak-guard (`scripts/firewall/apply.sh`).
- **Block IPv6** — включён по умолчанию, чтобы клиентский трафик не утекал в обход IPv4-туннеля.
- **TPROXY port** — меняйте только при конфликте (дефолт `12345`).
- **DNS** — `Split` резолвит домены локального региона напрямую, остальное — через DoH в туннеле;
  `All over DoH` отправляет всё через DoH.
- **Anti-DPI** — uTLS-отпечаток + опциональный XHTTP-паддинг.

Кастомные переопределения по доменам/IP (только в сплит-режимах) живут на **Dashboard** в виде двух
списков: *Direct (bypass VPN)* и *Via VPN* — по одной записи в строке: `домен`, `IP/CIDR`,
`geosite:NAME` или `geoip:NAME`.

Нажмите **Save & Apply**.

---

## 6. Подключение и проверка

**Dashboard → Turn on.** Статус идёт *Starting…* → *Connected*, как только Xray поднимется (UI
опрашивает и показывает ошибки вместо зависания).

Проверьте выходной путь:

- **Dashboard → Check exit IP** — пробит ip-api.com *через правила сплита*; вы должны увидеть страну
  вашего VPN-сервера. (Добавьте ip-api.com в список *Direct*, чтобы увидеть свой реальный IP.)
- Из шелла:
  ```sh
  # ubus call monkey-business check_exit '{"domain":"ip-api.com"}'
  # pidof xray && echo "xray running"
  # nft list table inet monkey_business        # ruleset TPROXY присутствует
  # logread | grep -iE 'xray|monkey-business'  # рантайм-логи
  ```
- С **LAN-клиента** (реальный тест — этот бокс ваш шлюз): зайдите на зарубежный сайт и проверьте
  наблюдаемый IP; локально-региональный сайт должен по-прежнему показывать ваш реальный IP.

---

## 7. Заметки по NanoPi R2S и решение проблем

- **Производительность.** У RK3328 нет аппаратного ускорения AES; реалистичная пропускная
  способность Reality/VLESS ~100–300 Мбит/с. Если ниже — это упор в CPU, а не ошибка конфига:
  тюньте XHTTP/sniffing и предпочитайте Reality более тяжёлым TLS-стекам.
- **Два NIC.** Один Ethernet-порт R2S висит за USB3; убедитесь, что ваш LAN-мост (`br-lan`) — тот,
  на котором клиенты. Firewall перехватывает `iifname "br-lan"` по умолчанию — если ваш LAN-интерфейс
  другой, задайте `uci set monkey-business.global.lan_iface=<iface>` и примените заново.
- **Запись в *Direct* будто игнорируется (например, `ping <IP>` с LAN-клиента — timeout).**
  `ping`/ICMP — невалидный тест: перехватывается только TCP/UDP, поэтому ICMP к любому публичному
  IP дропается kill-switch'ем независимо от того, есть ли адрес в *Direct*. Direct-маршрутизация
  происходит внутри Xray (обхода на уровне ядра нет), поэтому проверяйте через `curl`/`nc` (TCP)
  либо добавьте хост в *Direct* и подтвердите через **Dashboard → Check exit IP** — не пингом.
- **`geo databases missing` при Turn on.** Сначала выполните Раздел 3.
- **Застряло на «Starting…».** Xray упал — `logread | grep xray`. Обычные причины: неверные
  Reality-параметры в записи сервера или TPROXY-порт уже занят.
- **Конфиг переживает reboot/sysupgrade.** `/etc/config/monkey-business` — это UCI; держите его в
  keep-list для sysupgrade (по умолчанию так и есть), чтобы серверы и креды сохранялись.
- **`WARN: ubus-объект не поднялся` сразу после деплоя.** `rpcd restart` иногда оставляет `ubusd`
  живым, но не принимающим соединения (openwrt#9492) — на железе реже, чем в QEMU, но **случается**.
  `deploy-vm.sh` теперь сам детектит недоступный ubus и пересоздаёт `ubusd`+`rpcd`; форвардинг трафика
  не страдает (управление моргает на секунду). Если поймали wedge вне скрипта — восстановите вручную:
  `killall rpcd ubusd; rm -f /var/run/ubus/ubus.sock; /sbin/ubusd & sleep 2; /sbin/rpcd &` — или просто
  `reboot` (сама загрузка на железе нормальная; отдельный boot-hang только у QEMU dev-VM).
- **`apk` или `opkg`.** `deploy-vm.sh` ставит deps тем менеджером, что есть в сборке. Если нет ни того,
  ни другого — поставьте `xray-core kmod-nft-tproxy rpcd-mod-ucode ucode-mod-uci ucode-mod-fs curl` вручную.

---

Всё остальное (архитектура, разработка, dev-VM) — в основном
[README](../README.ru.md).
