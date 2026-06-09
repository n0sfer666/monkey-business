# Отчёт: 6 фиксов/фич UI (custom-flow, 2026-06-09)

Спека: `.context/specs/2026-06-09-ui-fixes-routing-failover.md`
План: `.claude/plans/2026-06-09-ui-fixes-routing-failover.md`

## Выполнено (все 6)
| # | Пункт | Статус | Проверка (живая VM) |
|---|-------|--------|---------------------|
| 1 | Fetch подписки без save | ✅ | `subscription_update {url}` → 4 сервера; url сохраняется при успехе |
| 2 | Turn on → Connected (не вечный Starting) | ✅ | `service_toggle` → running:true, `pidof xray` RUNNING |
| 3 | Settings Save&Apply без «no server selected» | ✅ | автовыбор; xPaddingBytes+dns в xray.json |
| 4 | Приоритеты + connect-time failover | ✅ | priority-поле; выбран первый доступный по приоритету |
| 5 | Custom direct/vpn + geo (.dat) | ✅ | custom-правила в xray.json (split-only); geoip/geosite.dat скачаны; xray -test ок |
| 6 | Трафик подписки на дашборде | ✅ | status.traffic ~21.5/300 GB + expire (заголовок Subscription-Userinfo) |

## Ключевые первопричины (найдены при отладке)
- `configApply` не передавал dns/anti_dpi → настройки не применялись.
- Никто не выставлял `selected.server` → «no server selected».
- `serviceToggle` не запускал xray → «Starting» навсегда; усугублялось `pgrep -x xray` (не матчит на BusyBox) → `pidof`.
- Вложенные `transport`/`reality` сервера терялись в UCI (только строки) → краш генератора; фикс: JSON на границе UCI.
- `uclient-fetch` не отдаёт заголовки ответа → для userinfo добавлен `curl`.
- Нет geo .dat → xray не стартует с geoip/geosite; добавлен `update-geo.sh`.

## Заблокировано / не доделано
- **Браузерные скриншоты UI**: навигация Claude-in-Chrome отклонялась диалогом доступа (на стороне
  пользователя). Поведение подтверждено авторитетно через ubus/xray на живой VM; визуальная проверка — за
  пользователем (VM запущена, http://localhost:8080, root/root).
- Runtime-failover (авто-переключение в сессии) — НЕ делалось по решению пользователя (только connect-time).

## Проверка
- `make test`: shellcheck (13) + ucode + js + **54 unit** — зелёные.
- T3 на dev-VM: реальный xray стартует с geo, все 6 сценариев через ubus.
- `.claude/.verify-state.json`: T3, vm-ubus-connect.

## Коммиты
- `feat(rpcd): server priority+selection, traffic userinfo, full apply, connect-on-toggle` (+ подхватил
  незакоммиченную работу прошлой задачи: README EN/HVF/import-fix)
- `feat(ui): live-url fetch, connect+poll, traffic, custom routing, geo download`
- `fix(rpcd): JSON-nest servers in UCI, curl userinfo capture, pidof status, preserve config on deploy`

## Дальше (необязательно)
- Снять скриншоты UI в браузере (нужен доступ Claude-in-Chrome).
- Реальный прогон трафика через туннель (LAN-клиент) — на железе/в netns.
