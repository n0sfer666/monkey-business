# Отчёт — Аудит direct-листа (2026-06-21)

## Задача
Найти ВСЕ причины, по которым запись в `custom_direct` (IP 81.85.75.40, ранее RU-подсети)
не приводит к прямой маршрутизации. Проверять фактическое состояние, не предполагать.

## Выполнено
- Аудит всех 7 слоёв из ТЗ (nft TPROXY, kill-switch, ip rule/route, Xray routing, генератор,
  формат записей, IPv6-block).
- Фактическая верификация: генератор прогнан в контейнере; рантайм снят с боевого R2S
  (nft/ip rule/route/xray.json, read-only).
- 3 причины найдены, 2 кода-фикса применены и закоммичены (`e783b83`), 1 причина — by design
  (документирована).

## Причины
| # | Причина | Слой | Статус |
|---|---------|------|--------|
| 1 | kill-switch `forward drop` дропает ICMP (ping) к публичным IP | firewall | by design; ping невалиден для проверки → curl/nc |
| 2 | sniffing `routeOnly:false` → IP-правило матчит переразрешённый IP → утечка в туннель | generator/Xray | **фикс: routeOnly:true** |
| 3 | `ipv6_block ::/0` перед custom-правилами → IPv6-whitelist блокируется | generator | **фикс: порядок правил** |

## НЕ баг (проверено)
- Парсинг IP/CIDR/comma — корректен (`replace` в ucode глобальный).
- UCI→Xray синхронен — живой xray.json содержит `{"ip":["81.85.75.40"],"direct"}` перед catch-all.
- `ip rule`/`route` — штатный TPROXY policy-routing.

## Изменённые файлы
- `src/generator/xray.uc` — routeOnly:true; custom-правила над ipv6-block.
- `test/fixtures/xray_bypass_ru.json`, `test/fixtures/xray_stage4.json` — снапшоты.
- `test/unit/generator_test.uc` — регресс-тест порядка.
- `.context/investigations/2026-06-21-direct-list-not-applied.md` — разбор.

## Коммиты
- `e783b83` fix(generator): reliable IP direct-list via sniffing routeOnly + ipv6 order

## Проверки
- T2 host: `make lint && make check && make test-unit` — green (28/28 generator).
- T3 device: read-only снимок боевого R2S подтвердил диагноз.

## Заблокировано / остаток
- Поведенческая T3 фикса (check_exit/curl-флип до-после) требует `make deploy
  HOST=root@192.168.1.1` — рестарт боевого шлюза, по согласованию времени с пользователем.
