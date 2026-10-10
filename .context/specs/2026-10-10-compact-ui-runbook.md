# Компактный UI — runbook ручной проверки

Прогоняется после каждой итерации в dev-VM (`make dev-up`, `make dev-deploy`, LuCI на
`http://localhost:8090`, ssh `root@localhost -p 2222`); на R2S — только готовая фича. Устаревший шаг
править в том же коммите, где меняется поведение.

## Подготовка
1. Деплой: `make dev-deploy` (VM) или `make deploy HOST=root@192.168.1.1` (R2S).
2. На роутере: `cd /www/luci-static/resources/view/monkey-business && ls kit model srv set`
   — 9 / 6 / 3 / 1 файлов; `ls commit.js subsection.js` — оба «No such file».
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
4. Servers: Ping all, переключение подписки, Fetch у подписки, Save & Apply формы серверов —
   индикатор «Unsaved Changes» гаснет, конфиг применяется.
5. Добавить ручной сервер по ссылке — поля заполнились (parse_uri).

## Итерация 2 — Servers: подписки

URL подписки в логи, скриншоты и отчёты не попадает. `<S>` — id новой подписки
(`uci show monkey-business | grep =subscription`).

### Панель
1. Servers ≥ 1100px: над таблицей панель *Subscriptions* — шапка с подписью «the active one is used
   first…» и кнопкой *+ Add subscription*, строка заголовков Role / Name / URL / Auto-update /
   Traffic, по строке на подписку (бейдж *active* у активной, *reserve* у остальных). Старой
   CBI-секции *Subscriptions* с *Fetch subscription* нет.
2. 722 / 800px: колонки сжимаются, Fetch / Ping не переносятся, горизонтального скролла нет.
3. ≤ 720px: строка — плитка (бейдж, имя, корзина; URL на всю ширину; полоса трафика; Fetch / Ping;
   *Auto-update* с переключателем и ползунком 10 min…2 h); заголовков колонок нет, кнопка — *+ Add*;
   корзина 36px с видимой иконкой.
4. Тёмная и светлая тема: панель и строки в палитре Settings.

### Add
1. *+ Add subscription* → шторка, имя по умолчанию «Subscription N+1». Пустой URL или `ftp://x` →
   подсказка под полем, *Add & fetch* неактивна.
2. URL недоступного хоста (`https://192.0.2.1/nope`) → ~25 с *Fetching…*, затем плашка «Couldn't
   fetch the subscription — fetch failed — nothing was saved»; `uci show monkey-business | grep
   =subscription` — новой секции нет (и через минуту тоже нет).
   Пока идёт *Fetching…*, Esc и клик по подложке шторку не закрывают.
3. Реальный URL → шторка закрылась без перезагрузки страницы, серверы в таблице, уведомление
   «Servers fetched for “…”: N»; `uci show monkey-business | grep -c ".sub='<S>'"` = N.
4. Свежая установка (пустая дефолтная `subscription`): подсказка шторки «Becomes the active
   subscription», новая строка *active*, `uci get monkey-business.global.active_sub` = `<S>`. Если
   активная уже с серверами — подсказка «A reserve until…», новая строка *reserve*.

### Инлайн-правки
1. URL в строке показан как `https://••••••/••••••`; фокус — реальный URL, Esc/blur — снова маска.
2. Name пустой → красная рамка, не сохраняется; Enter на новом имени — индикатор Unsaved Changes.
3. Интервал (десктоп): `5` → подсказка «Minimum is 10 min…», после Enter — «every 10 min»; `500` →
   «every 2 h»; `0` → «off». Легаси 86400 показан как «every 2 h».
4. *Save & Apply* → `uci get monkey-business.<S>.name / .auto_update / .update_interval` — новые
   значения (7200 для 2 h, `auto_update=0` при off, интервал при этом сохранён); уведомлений
   «Servers fetched» нет (URL не менялся).
5. Мобилка: ползунок на 30 → *Save & Apply* → `update_interval=1800`; переключатель off →
   `auto_update=0`, `update_interval` остался 1800.
6. Правка имени → *Reset* → прежнее имя.
7. Сменить URL подписки → *Save & Apply* → «Servers fetched for “…”», серверы перечитаны без
   перезагрузки страницы.

### Fetch / Ping / Delete
1. *Fetch* у подписки без URL → «Enter a subscription URL first.»; с URL → страницу закрывает
   шторка «Fetching “…”…» (Esc не закрывает), затем «Servers fetched for “…”: N».
2. Переименовать другую подписку (Enter, без Save) → *Fetch* → `uci get
   monkey-business.<sid>.name` уже новое, `uci changes monkey-business` пусто, имя в строке осталось.
3. *Ping* → «Ping: N ok, N auto-off, N n/a», колонка *Ping* таблицы заполнилась.
4. Корзина у активной → шторка «Delete “…”?» с числом серверов и тем, какая станет активной;
   *Cancel* — ничего не изменилось. *Delete* → строка и её серверы пропали из таблицы, ручные на
   месте, следующая подписка *active*; *Save & Apply* → секции нет, `global.active_sub` = следующая,
   серверов с `.sub='<удалённая>'` нет.
5. Корзина у подписки → *Delete* → сразу *Fetch* у другой (без Save & Apply) → секции удалённой нет,
   серверов с `.sub='<удалённая>'` нет (раньше воскресали сиротами).

### Подписка в фоне
`subupdate.sh` раз в минуту по cron: интервал < 600 c поднимается до 600, > 7200 опускается до 7200
(тесты `subupdate_test.sh` 6/6a/6b).

## Результат
Итерация 1 — 30/30, итерация 2 — 52/52 (Playwright в VM: 1280 / 800 / 722 / мобилка, тёмная и
светлая). Console: ошибок приложения нет; `ERR_CONNECTION_RESET` / `L is not defined` при загрузке
страницы — сбросы slirp-проброса QEMU (`luci.js` не догрузился), на R2S не воспроизводятся.
