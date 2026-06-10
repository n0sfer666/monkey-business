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
make dev-up                # скачает образ, поднимет VM (SSH :2222, LuCI :8090)
make dev-ssh               # ssh root@localhost -p 2222
make dev-down              # остановить
```
Переопределение: `MB_IMMORTALWRT_URL`, `MB_VM_SSH_PORT`, `MB_VM_HTTP_PORT`, `MB_VM_MEM`.

## Статус проверки (T2 smoke)
- **BLOCKED на этом хосте:** `qemu-system-aarch64` не установлен (macOS без qemu).
- Скрипты готовы; для подтверждения boot выполнить у себя:
  `brew install qemu && make dev-up`, затем `make dev-ssh` и открыть `http://localhost:8090`.
- Тесты для этого шага не требуются (этап 1 освобождён); скрипты проходят shellcheck.

## Предпросмотр приложения (preview-флоу)
```sh
make dev-up         # boot
make dev-provision  # один раз: DHCP + пароль root/root + LuCI
make dev-deploy     # раскладка + рантайм-deps + reload rpcd; печатает URL
```
LuCI: http://localhost:8090 (root/root) → Services → monkey-business VPN.
- `deploy-vm.sh` теперь неинтерактивен через `MB_VM_SSH_PASS` (sshpass); Makefile-цель `dev-deploy`
  передаёт `root`. Ставит недостающие deps идемпотентно (для UI хватает uci/fs+rpcd-mod-ucode из LuCI;
  xray/tproxy — только для запуска сервиса). После рестарта проверяет регистрацию ubus-объекта.
## ВАЖНО: настоящая причина «не регистрировался объект / Failed to connect to ubus»
Две macOS-деплой-баги (обе исправлены, проверено на устройстве — deploy печатает «OK: ubus-объект ... зарегистрирован»):
1. **Относительный `import` в точке входа плагина.** rpcd-mod-ucode компилирует плагин ИЗ БУФЕРА
   (без пути) → `./lib/...` не резолвится → плагин молча падает. Фикс: абсолютный путь импорта.
   Через `ucode -R file.uc` (есть путь) работает — поэтому баг был незаметен; через `ucode -R -`
   (буфер, как у rpcd) — падает. Файл плагина в `root/` не покрыт `check-syntax.sh`.
2. **macOS `tar` кладёт AppleDouble `._*`.** rpcd-mod-ucode давится `._monkey-business.uc` —
   косметический шум (НЕ причина wedge). Фикс: `COPYFILE_DISABLE=1 tar --exclude '._*'` + уборка
   на цели. ВАЖНО: `._*` уходят и на реальный R2S при деплое с macOS.
3. **Эмуляционный wedge ubusd:** boot-time ubusd в QEMU виснет при `/etc/init.d/rpcd restart`
   (жив, но не принимает соединения; openwrt#9492). Лечит только свежий ubusd. `deploy-vm.sh` при
   `MB_UBUS_RESPAWN=1` (Makefile `dev-deploy`, т.е. dev-VM) пересоздаёт ubusd+rpcd; на железе нет.
   Итог: `make dev-deploy` стабильно оставляет рабочую VM.

## Отдельная проблема среды: guest-reboot виснет
`reboot` гостя виснет на «procd: - ubus -» (ubusd не поднимается на ребуте — гонка QEMU `-M virt`,
openwrt#9492). НЕ связано с `._` и НЕ лечится HVF. Рабочий путь: `make dev-down` → `make dev-up`
(холодный старт свежего QEMU работает), не `reboot`. Совсем зависла — `sh scripts/dev-vm.sh clean`.

## Тестовое окружение (отдельно от dev-VM)
Unit/lint гоняются в Docker-контейнере (`Dockerfile.test`, alpine+ucode+shellcheck) —
это не dev-VM, а быстрый контейнер для host-тестов с macOS. netns-интеграция (этап 3)
требует привилегированного Linux-контейнера или dev-VM.
