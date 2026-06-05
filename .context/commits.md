# Коммиты

- Стиль: **Conventional Commits**, на английском.
- Формат: `type(scope): subject` — subject в imperative, без точки, ≤ ~72 символов.
- Типы: `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `build`, `ci`.
- Scope: `parser`, `generator`, `rpcd`, `luci`, `firewall`, `dns`, `dev`, `ci`, `context`.
- Без `Co-Authored-By`, без AI-подписей.
- Не коммитить код, не прошедший `make lint && make check && make test-unit`.
- Ветка разработки: `dev`.

Примеры:
- `feat(parser): add base64 vless subscription parser`
- `test(generator): add golden snapshot for bypass-ru routing`
- `chore(context): bootstrap project context and test harness`
