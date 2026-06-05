# Dev-среда (этап 1)

## Цель
Эмуляция ImmortalWrt **aarch64** в QEMU для быстрой разработки UI/логики; финальные
сетевые и перф-тесты — на реальном NanoPi R2S.

## Почему armsr/armv8
NanoPi R2S — rockchip/armv8 (RK3328, aarch64). Для QEMU используем generic
**armsr/armv8** (ARM SystemReady) combined-efi образ ImmortalWrt: та же ARMv8-архитектура,
грузится в `qemu-system-aarch64 -M virt` через UEFI (edk2). Прошивка R2S-специфики —
только на железе.

## Запуск
```sh
brew install qemu          # на macOS qemu по умолчанию отсутствует
make dev-up                # скачает образ, поднимет VM (SSH :2222, LuCI :8080)
make dev-ssh               # ssh root@localhost -p 2222
make dev-down              # остановить
```
Переопределение: `MB_IMMORTALWRT_URL`, `MB_VM_SSH_PORT`, `MB_VM_HTTP_PORT`, `MB_VM_MEM`.

## Статус проверки (T2 smoke)
- **BLOCKED на этом хосте:** `qemu-system-aarch64` не установлен (macOS без qemu).
- Скрипты готовы; для подтверждения boot выполнить у себя:
  `brew install qemu && make dev-up`, затем `make dev-ssh` и открыть `http://localhost:8080`.
- Тесты для этого шага не требуются (этап 1 освобождён); скрипты проходят shellcheck.

## Тестовое окружение (отдельно от dev-VM)
Unit/lint гоняются в Docker-контейнере (`Dockerfile.test`, alpine+ucode+shellcheck) —
это не dev-VM, а быстрый контейнер для host-тестов с macOS. netns-интеграция (этап 3)
требует привилегированного Linux-контейнера или dev-VM.
