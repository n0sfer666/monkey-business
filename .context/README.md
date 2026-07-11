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
- `decisions/` — ADR.

Не в репозитории (локальные, в `.gitignore`): `notes/` — заметки по подсистемам (`watchdog.md`,
`boothealth.md`, dev-среда); `investigations/` — разборы инцидентов; `.claude/` — планы и отчёты.
Долгоживущее знание из них переносить сюда (`architecture.md`, `specs/`, `decisions/`) или в
`docs/`.

Проект: VPN-клиент Reality/VLESS/XHTTP для роутера, аналог passwall/v2rayA с простым UI.

Внешняя докуа двуязычна: `README.md`/`docs/install-nanopi.md`/`docs/sd-expand-macos.md` — canonical
(EN), рядом `*.ru.md` — перевод (кросс-линки EN↔RU вверху). Хост-команды с env-var префиксами имеют
отдельный nushell-блок (`with-env {…} {…}` / `$env.X = …`); router-команды (`#`/ssh/apk/nft/ubus) —
без nushell. При правке доков синхронизировать EN+RU и nushell-блоки.
