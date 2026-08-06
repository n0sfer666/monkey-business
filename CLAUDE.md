# monkey-business — правила проекта

## СТРОГИЕ ПРАВИЛА

1. **Контейнеры не оставлять работающими.** `make lint/check/test-unit/test-integ` поднимают Docker
   (`monkey-business-test`, `monkey-business-integ`). Проверки закончены — контейнеры погасить
   (`docker ps -q | each { docker stop $in }` для наших, или `docker stop <id>` поимённо). То же для
   dev-VM в QEMU: не нужна — `make dev-down`. Ресурсы Мака ограничены, забытый контейнер жрёт их всю
   сессию.
