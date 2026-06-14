# .context — monkey-business

Проектный контекст для работы с Claude Code.

- `stack.md` — стек, платформа (NanoPi R2S / ImmortalWrt), компоненты, домен.
- `architecture.md` — слои, потоки данных, границы тестируемости.
- `conventions.md` — код-стайл ucode/shell, правила модулей.
- `testing.md` — стратегия тестирования (кратко; полная — в specs/).
- `commits.md` — стиль коммитов (Conventional Commits).
- `checks.md` / `checks.json` — команды проверки (Makefile-цели).
- `env.md` — переменные окружения (без значений).
- `specs/` — спецификации фич. Главная: `2026-06-05-monkey-business-vpn-client.md`.
- `notes/` — заметки (dev-среда и пр.).

Проект: VPN-клиент Reality/VLESS/XHTTP для роутера, аналог passwall/v2rayA с простым UI.
План разработки: `.claude/plans/2026-06-05-monkey-business.md`.

Внешняя докуа двуязычна: `README.md`/`docs/install-nanopi.md` — canonical (EN), рядом `*.ru.md` —
перевод (кросс-линки EN↔RU вверху). Хост-команды с env-var префиксами имеют отдельный nushell-блок
(`with-env {…} {…}` / `$env.X = …`); router-команды (`#`/ssh/apk/nft/ubus) — без nushell.
При правке доков синхронизировать EN+RU и nushell-блоки.
