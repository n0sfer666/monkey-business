# Компактный UI (LuCI) — спецификация

Статус: архитектура согласована 2026-10-10 (ADR `decisions/2026-10-10-own-dom-ui.md`); итерация 1
сделана 2026-10-10 (kit, `api.js`, `store.js`, Settings) — ждёт прогона runbook на R2S
(`specs/2026-10-10-compact-ui-runbook.md`) и согласования светлой палитры (`kit/tokens.js`).
Макет: https://claude.ai/artifact/Qi9eCMkVJJSUMzKcLT3TFF (версия 30). Источник правды по виду —
борды макета; эта спека фиксирует поведение и архитектуру.

## Цель
Переписать три экрана (Dashboard / Servers / Settings) в компактный UI по макету: одна разметка на
десктоп и мобилку, тёмная и светлая тема через токены, без копипаста, бэкенд проверяет всё, что
пишет. Внешний контракт (UCI-схема, ubus-методы, которые зовут cron/watchdog) не ломается.

## Решения дизайна (зафиксированы в макете)
- Вкладки Dashboard / Servers / Settings видны на каждом экране — это меню LuCI (`menu.d`,
  firstchild), не наш компонент. Заголовков h1 «Servers»/«Settings» под ними нет.
- Кнопки создания («+ Add subscription», «+ Add server») — акцентный тинт; сплошной primary только
  у Save & Apply.
- Подписка правится в строке: Name и URL — инлайн-поля (пунктирная рамка, как у Auto-update), URL
  замаскирован до фокуса. В строке: Fetch, Ping, корзина. Модалка подписки — только «Add»:
  Name + URL, «Add & fetch»; провал скачивания — красная плашка, ничего не сохранено.
- Auto-update: 0 = off, иначе 10–120 мин (десктоп — число, мобилка — switch + slider шаг 5).
- Сервер задаётся одной ссылкой. Модалка: Link (живой вердикт + сводка-чипы распознанного) и
  Name (необязательно, по умолчанию из `#тега` ссылки / адреса). Ручного ввода полей и Advanced нет.
  Edit — только у ручных серверов (ссылка предзаполнена); серверы подписки не редактируются —
  у них Off и Delete.
- Удаление сервера и подписки — всегда через подтверждение. Сервер подписки: Cancel / Turn off /
  Delete, «вернётся при следующем обновлении». Подписка: «её N серверов удалятся, ручные останутся»;
  активная — плюс «X станет активной».
- Мобилка: модалки — нижние шторки, кнопки подтверждения стопкой (Delete первой); серверы — плитки
  с ⋮-меню (Ping, Edit для ручных, Off, Delete), перестановка — режим «тап по плитке → тап по месту».
- Пинг: колонка Ping, «Ping all», «Sort by ping» (порядок применяется по Save & Apply);
  hysteria2 — `n/a · UDP`, не авто-отключается; >1 с или нет ответа — auto-off до следующей проверки.

## Решения архитектуры (согласованы)
1. **Свой DOM вместо CBI.** `form.Map` / `GridSection` / `TypedSection` уходят полностью: инлайн-поля,
   плитки, шторки и ⋮-меню на CBI не ложатся, а обходы (`MutationObserver`, sticky-хак, `_show`
   для валидации) — источник багов. Разметка — `E()`, состояние — простой объект на экран,
   перерисовка секции целиком по изменению (без виртуального DOM).
2. **Модель изменений — staged UCI LuCI** для Servers и Settings: `uci.set/add/remove/move` →
   Save = `uci.save()` (индикатор изменений LuCI), Reset = `uci.unload` + перерисовка,
   Save & Apply = `store.commit()` (без rollback, см. память про `uci.apply`) → `subscription_update`
   для подписок с изменённым URL → `config_apply`, если сервис запущен. Dashboard и модалки
   Routing/Geo, переключение подписки, Turn on/off — как сейчас, сразу через RPC.
3. **Одна разметка, адаптив через CSS.** Брейкпоинт 720px. Строка сервера на десктопе — строка
   грида, на мобилке — плитка; кнопки действий и ⋮-меню рендерятся оба, лишнее прячет CSS. Модалка
   и шторка — один компонент `kit/sheet`, вид задаёт CSS.
4. **Токены темы.** CSS-переменные `--mb-*` (bg, panel, line, line-strong, text, muted, accent,
   ok/warn/err + их тинты, primary). Тёмные значения — из макета, светлые — подобрать в итерации 1.
   На R2S тема bootstrap: она ставит `data-darkmode="true"|"false"` на `<html>` — по нему и
   переключаемся; без атрибута (другая тема) — `prefers-color-scheme`. CSS живёт в JS-модуле `kit/style.js` (вставляет `<style>` один раз):
   так он идёт через тот же кэш-бастинг `?v=`, что и JS, и не требует строки в `deploy-vm.sh`.
5. **Один модуль RPC.** Все `rpc.declare` — в `api.js` (сейчас `status`, `servers_list`,
   `config_apply` объявлены по 2–3 раза).
6. **Проверки — на бэкенде, фронт их только показывает.** Ссылка — `parse_uri` (есть), правила
   маршрутизации — новый `routing_check` (тот же приём: чистый метод без побочных эффектов,
   фронт зовёт с debounce 400 мс). Дублей валидаторов в JS нет.
7. **Чистая логика фронта — в `model/`, без DOM и LuCI**, покрывается node-тестами.

## Раскладка фронта
```
view/monkey-business/
  dashboard.js servers.js settings.js   view: load → state → render; Save/Reset/Apply-хуки
  api.js                                все rpc.declare
  store.js                              staged UCI: get/set/add/remove/move, dirty, save/reset/apply
  kit/  style.js sheet.js confirm.js switch.js seg.js menu.js inline.js tip.js field.js
  model/ dirty.js datatype.js settings.js subs.js pingtext.js interval.js order.js servers.js confirmtext.js
  dash/ status.js traffic.js routing.js rules.js geo.js serverlist.js hysteria.js
  srv/  subpanel.js subrow.js subsheet.js serverrow.js serversheet.js pingbar.js
  set/  sections.js
```
`kit/` не знает домена; `model/` не знает DOM; `dash/ srv/ set/` склеивают одно с другим.
Файлы ≤ 200 строк. Старые модули (`serverfields`, `serveropt`, `serverlink`, `subsection`,
`pinggrid`, `commit` → в `store`) удаляются в той итерации, где заменены.

## Бэкенд
- **`routing_check {direct, proxy}`** (новый, read): `[{list, line, code}]`. Логика —
  `src/lib/rules.uc` `validateRules`; `classifyList` (`src/generator/routing.uc`) переходит на неё.
- **`set_routing`**: отклоняет невалидное `{error:'invalid_rules', items:[…]}` до записи в UCI.
- **`server_link {id}`** (новый, write — отдаёт секреты): ссылка ручного сервера для Edit.
  Сериализатор `src/lib/serveruri.uc` `serverToUri`; тест — round-trip `parse(serverToUri(s)) == s`
  по фикстурам vless/reality/xhttp/grpc/hy2(obfs, mport, pin).
- **`subscription_add {name, url}`** (новый, write): создать секцию → скачать → при провале удалить
  секцию и вернуть ошибку («nothing was saved»). Если активная подписка пустая (без URL и серверов —
  дефолтная `subscription` свежей установки), новая становится активной. Скачивание до ~25 с (`curl -m 25`) — дольше
  дефолтного RPC-таймаута LuCI (20 с), поэтому `api.js` поднимает его до 60 с для
  `subscription_add` / `subscription_update`.
- **Интервал**: `update_interval` — секунды, допустимо 600–7200; clamp в `subupdate.sh`
  (`MB_SUB_MIN` 300 → 600, новый `MB_SUB_MAX` 7200), дефолт в `root/etc/config` 86400 → 3600.
  Старое 86400 при чтении показывается как 120 мин и пишется так при следующем Save.
- ACL: новые методы в `acl.d`. Регрессионные тесты на каждый метод — `rpcd_test.uc`.

## Тесты
- ucode: `rules_test.uc`, `serveruri_test.uc` (round-trip), `rpcd_test.uc` (+3 метода,
  `set_routing` reject), `subupdate_test.sh` (границы 600/7200).
- JS: `test/js/*.test.js` под node (уже в образе): загрузчик подменяет `baseclass.extend` и
  исполняет модуль из `model/`. Подключить в `test/run-unit.sh`.
- Визуал и поведение в LuCI — ручная проверка пользователем на R2S по runbook итерации.

## Итерации
Каждая: десктоп + мобилка одного экрана в одной сессии; lint/check/test-unit; code-reviewer;
runbook ручной проверки — прогон в dev-VM (QEMU); на R2S — только готовая фича.
1. **Kit + токены + Settings.** `kit/*`, `style.js`, `api.js`, `store.js`, JS-тест-харнесс; Settings
   на новом DOM. Проверяет тему (тёмная/светлая), брейкпоинт и staged-модель на самом простом экране.
2. **Servers: подписки.** Инлайн Name/URL/интервал, Add-шторка, удаление с подтверждением, Fetch/Ping.
   Бэкенд: `subscription_add`, интервал 600–7200. Готово: панель `srv/subpanel.js` над старым
   CBI-гридом серверов, `subsection.js` удалён.
3. **Servers: серверы.** Грид/плитки, Ping all, Sort by ping, Off, перестановка, ⋮-меню,
   шторка сервера (только ссылка), удаление с подтверждением. Бэкенд: `server_link`.
4. **Dashboard.** Статус, трафик, Routing-модалка (`routing_check` + отказ `set_routing`),
   Geo-модалка, список серверов, hysteria.
5. **Зачистка.** Удаление остатков CBI, доки (README/runbook EN+RU), `.context/architecture.md`.

## Риски
- Удаление `serveropt.js` снимает миграцию JSON-блоба → плоские поля при сохранении. Запись
  ссылки ручного сервера обязана писать плоские поля и снимать блоб (тест в итерации 3).

## Решённые вопросы
- Светлая палитра «холодный серый» (`kit/tokens.js`) принята как есть (2026-10-10).
- Fetch / Add при несохранённых правках: сначала `map.save` + коммит (как Save & Apply, без
  `config_apply`), потом запрос (2026-10-10). Только staged-дельты теряются: бэкенд пересоздаёт
  анонимные секции server, и дельты на старые имена libuci отбрасывает (удалённые серверы
  воскресали сиротами). На время запроса страница закрыта шторкой `kit/progress.js`, иначе
  `store.reset` после ответа стёр бы правки, сделанные за время ожидания.
