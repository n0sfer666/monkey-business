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
| Сборка ipk | `make package` | T2 (нужен OpenWrt SDK) |
| Dev-VM | `make dev-up` / `make dev-ssh` | T2 (нужен qemu) |

Перед коммитом минимум: `make lint && make check && make test-unit` зелёные.
Записать `.claude/.verify-state.json` с актуальным tier/result.
