# Компактный UI — runbook ручной проверки на R2S

Проверяет пользователь на живом R2S после каждой итерации. Устаревший шаг править в том же
коммите, где меняется поведение.

## Подготовка
1. Деплой: `make deploy HOST=root@192.168.1.1` (или nushell
   `with-env { MB_VM_SSH_HOST: "root@192.168.1.1", MB_VM_SSH_PORT: "22" } { sh scripts/deploy-vm.sh }`).
2. На роутере: `ls /www/luci-static/resources/view/monkey-business/kit /www/luci-static/resources/view/monkey-business/model /www/luci-static/resources/view/monkey-business/set`
   — 9 / 3 / 1 файлов; `ls /www/luci-static/resources/view/monkey-business/commit.js` — «No such file».
3. В браузере жёсткая перезагрузка (Cmd+Shift+R) на каждой странице приложения.
4. Открыть DevTools → Console: на всех шагах ниже — без красных ошибок.

## Итерация 1 — Settings, тема, api.js

### Тема
1. System → System → Language and Style → Design: `bootstrap-dark` → Settings тёмная (фон панелей
   `#212429`, текст светлый).
2. `bootstrap-light` → светлая палитра «холодный серый» (панели белые, рамки `#dde1e6`, текст
   `#1c2025`). Контраст подсказок читаемый.
3. `bootstrap` (auto) → следует системной теме macOS (переключить Appearance — меняется без
   ошибок после перезагрузки страницы).

### Раскладка
1. Окно ≥ 1100px: три панели General / DNS / Anti-DPI в ряд, кнопки Reset / Save / Save & Apply —
   справа сверху, под вкладками нет заголовка «Settings», футера LuCI с кнопками внизу нет.
2. Сузить до ~800px: панели переносятся (2 + 1), ничего не обрезано, нет горизонтального скролла.
3. ≤ 720px (DevTools → iPhone 12/14, и с телефона): одна колонка; селекты Log level / DNS mode /
   TLS fingerprint и поля Direct DNS / DoH URL — под подписью на всю ширину; порт — справа 96px;
   чекбоксы ~22px; кнопки — липкая панель внизу экрана, Save & Apply растянута.

### Staged-модель
1. Открыть Settings без правок: Reset и Save неактивны, Save & Apply активна.
2. Снять Kill-switch → Reset и Save активны. Вернуть галку → снова неактивны.
3. Поменять Log level → Reset → значение вернулось, кнопки неактивны.
4. Поменять Log level → Save → в шапке LuCI появился индикатор «Unsaved Changes: 1»,
   Save неактивна. На роутере `uci changes monkey-business` показывает правку.
5. Save & Apply → уведомление «Configuration applied.» (VPN включён) или «Saved. The VPN is off —
   …» (выключен); индикатор пропал; `uci get monkey-business.global.log_level` = новое значение;
   `uci changes monkey-business` пусто.
6. Флаги пишутся явно: снять Block IPv6 → Save & Apply → `uci get monkey-business.global.ipv6_block`
   = `0`; вернуть → `1`. Вернуть всё к исходным значениям.
7. Нажать Save & Apply и сразу Reset — Reset и Save неактивны, пока операция идёт.

### Валидация порта
1. TPROXY port = `0`, `70000`, `abc`, пусто → под строкой красный текст «Enter a number from 1 to
   65535», рамка поля красная, Save и Save & Apply неактивны.
2. Вернуть `12345` → ошибка исчезла, кнопки активны.

### Регресс после переноса RPC в api.js
1. Dashboard: статус, трафик, режим маршрутизации (сменить и вернуть), Split lists (Save),
   Geo (статус размеров), Hysteria (статус), список серверов с Ping — всё работает.
2. Turn off → Turn on: подключается, статус Running.
3. Check exit — показывает IP.
4. Servers: Ping all, переключение подписки, Fetch subscription, Save & Apply формы серверов —
   индикатор «Unsaved Changes» гаснет, конфиг применяется.
5. Добавить ручной сервер по ссылке — поля заполнились (parse_uri).

## Результат
Скриншоты Settings: тёмная десктоп, светлая десктоп, мобилка — приложить к согласованию светлой
палитры (открытый вопрос спеки).
