# Проверки

Все проверки гоняются в Linux-контейнере (`Dockerfile.test`, alpine+ucode+shellcheck),
т.к. macOS-хост не имеет ucode/nftables/netns.

| Что | Команда | Уровень |
|-----|---------|---------|
| Синтаксис ucode (types-эквивалент) | `make check` | T1 |
| Линт (shellcheck + ucode + eslint) | `make lint` | T1 |
| Unit/snapshot тесты | `make test-unit` | T2/T4 |
| Интеграция (netns) | `make test-integ` | T3 |
| Всё разом | `make test` | — |
| Обновить образ проверок | `make test-build` | — (нужна сеть) |
| Сборка ipk | `make package` | T2 (нужен OpenWrt SDK) |
| Dev-VM | `make dev-up` / `make dev-ssh` | T2 (нужен qemu) |

Перед коммитом минимум: `make lint && make check && make test-unit` зелёные.
Записать `.claude/.verify-state.json` с актуальным tier/result.

## Сети нет / Docker Hub недоступен

Проверки сетью не пользуются: образ берётся с диска, пересборка — только когда образа нет или
`Dockerfile.test` менялся (`scripts/docker-image.sh`). Сборка не прошла, а образ есть — печатается
предупреждение и проверки идут дальше. Подробности и правило — `decisions/2026-08-07-offline-checks.md`.

Если образа нет вовсе, а деплой нужен сейчас: `MB_SKIP_CHECKS=1 make deploy HOST=root@<ip>` (nushell:
`with-env {MB_SKIP_CHECKS: "1"} { make deploy HOST=root@<ip> }`).
