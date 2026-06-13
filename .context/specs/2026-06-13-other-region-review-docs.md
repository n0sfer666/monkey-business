# Спека: local_region "other" + ревью проекта + документация (2026-06-13)

## Контекст
Четыре независимые задачи в одном прогоне `/custom-flow`:
1. **Фича**: в Settings → Local region добавить опцию `other` = VPN passthrough (весь трафик direct).
2. **Ревью**: независимое (свежим взглядом) ревью каждого модуля проекта + чинить всё найденное.
3. **README** (англ.): install → developers → troubleshooting (все известные dev-кейсы) →
   feedback-секция (GitHub Issues/Discussions). Лицензия GPL-3.0 + файл LICENSE.
4. **NanoPi-гайд**: отдельный развёрнутый install-док (ImmortalWrt уже стоит).

Repo: `github.com/n0sfer666/monkey-business`. Публикуется как open-source (англ. внешняя докуа).

## Требования

### F1 — local_region "other" (passthrough)
- `settings.js`: в ListValue `local_region` добавить `other` с понятным лейблом
  («Other — all traffic direct (no VPN routing)») и обновить tooltip.
- `xray.uc/buildRouting(g)`: если `local_region == "other"` — игнорировать `routing_mode` и
  custom-списки, вернуть passthrough-правила: (если `ipv6_block`) block `::/0`, затем
  `{network:"tcp,udp", outboundTag:"direct"}`. Proxy-outbound не используется.
- `xray.uc/buildDns(dns, region, ipv6Blocked)`: если `region == "other"` — НЕ ссылаться на
  `geosite:other` (невалидная категория → `xray -test` падает). Вернуть единственный сервер
  `direct_dns` (всё резолвится напрямую), `queryStrategy` как прежде.
- Default в `/etc/config/monkey-business` не меняется (остаётся `ru`).

### F2 — Независимое ревью + фиксы
- Ревью по группам модулей (свежим взглядом, независимо друг от друга):
  - backend-логика: `parser/subscription.uc`, `lib/uri.uc`, `generator/xray.uc`, `rpcd/handlers.uc`;
  - рантайм/device: `root/usr/share/rpcd/ucode/monkey-business.uc`, `init.d`, `geo.sh`, `firewall/*`;
  - frontend: `luci/.../dashboard.js`, `servers.js`, `settings.js`, `menu.d`, `acl.d`;
  - dev/build/test: `Makefile`, `scripts/*.sh`, `Dockerfile.*`, `test/*`.
- Критерии: реальные баги, безопасность (инъекции в shell-вызовы, экранирование, секреты в логах),
  POSIX-sh/shellcheck, ucode-идиомы, DRY/KISS/SOLID, файлы >200 строк, мёртвый код,
  нарушения конвенций проекта.
- Чинить ВСЁ найденное (решение пользователя), кроме среднериск. рефакторингов, ломающих контракт
  без необходимости — такие выносить в отчёт. Каждый фикс — под проверкой `make test`.

### F3 — README (англ.)
Структура строго: (1) краткое описание; (2) **Install** (как поставить на роутер — ipk/deploy);
(3) **Development** (dev-окружение, контейнерные проверки, dev-VM); (4) **Troubleshooting** —
собрать ВСЕ известные dev-кейсы (из `.context/notes/dev-env.md`, README, dev-log);
(5) **Feedback** — GitHub Issues/Discussions (README-секция, без .github-шаблонов);
(6) **License** — GPL-3.0. Англ., лаконично, для внешнего читателя с GitHub.

### F4 — LICENSE
Файл `LICENSE` с полным каноническим текстом GPL-3.0 в корне репо.

### F5 — NanoPi install guide
`docs/install-nanopi.md` (англ., развёрнуто). Исходные условия: ImmortalWrt уже на R2S, есть SSH.
Покрыть: проверка платформы/места, рантайм-зависимости (xray, kmod tproxy/nft), два пути установки
(сборка ipk через SDK **или** `deploy-vm.sh` по SSH на R2S), скачивание geo, настройка
подписки/серверов, включение, проверка сплита (`check_exit`/`dev-test-split`), типовые проблемы R2S.

## Edge cases (F1)
- `other` + `routing_mode=global` → всё равно passthrough (mode игнорируется).
- `other` + custom_proxy непустой → игнорируется (passthrough = всё direct).
- `other` + `dns.mode=split` → DNS = только direct_dns, без `geosite:other`.
- `other` + `ipv6_block=1` → block `::/0` сохраняется (нет ipv6-утечки).
- Существующие golden-снапшоты (region=ru) не меняются → не трогать фикстуры.

## Риски и митигации
| Риск | Митигация |
|------|-----------|
| `geosite:other`/`geoip:other` → xray -test падает | special-case в buildRouting+buildDns, не ссылаться на категорию |
| «Чинить всё» → регрессии | каждый фикс под `make test` (lint+check+unit), golden-снапшоты пинят генератор |
| Удаление полезных gotcha-комментариев при «причёсывании» | НЕ трогать комментарии, документирующие реальные грабли; чистим только мусор |
| README теряет известные кейсы | troubleshooting собирается из dev-env.md + dev-log, сверка |

## Тестовая стратегия
- **F1 (T4, unit)**: новые тесты в `generator_test.uc` — buildRouting(other) passthrough,
  other+ipv6_block, other+global+custom (нет proxy-правил), buildDns(other)=только direct_dns.
  Базово `make test` зелёный.
- **F2 (T1/T2)**: после фиксов `make test` (lint + ucode/js syntax + unit) зелёный.
  Где затронут генератор/парсер — golden-снапшоты сверены. shellcheck-чистота скриптов.
- **F3/F4/F5 (T1)**: docs — вычитка, проверка ссылок/команд на соответствие Makefile/скриптам.
- T3 (dev-VM/железо) — blocked в этом прогоне (требует запущенной VM/R2S); инструкции готовы.

## DoD
- `local_region=other` даёт passthrough-конфиг, проходящий `xray -test` (логически: нет
  невалидных geo-категорий); unit-тесты покрывают F1; `make test` зелёный.
- Ревью проведено по всем модулям; найденные проблемы исправлены или вынесены в отчёт; `make test` зелёный.
- README перестроен (install→dev→troubleshooting→feedback→license), GPL-3.0, файл LICENSE есть.
- `docs/install-nanopi.md` написан, команды сверены с Makefile/скриптами.
