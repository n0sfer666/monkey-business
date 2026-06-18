# Boot-resilience (boothealth)

Модуль `root/usr/share/monkey-business/boothealth.sh` + init.d `root/etc/init.d/mb-boothealth`.
Корень инцидента 2026-06-18: грязный ребут во время фриза → повреждение ext4 → «не включилось».

## Картина ФС R2S
Образ — **MBR, s2 = единый чистый ext4 rootfs** (НЕ squashfs+overlay; см. [[sd-expand-macos]]).
Грязное отключение питания корраптит сам root. Журнал ext4 чинит метаданные при монтировании ядром,
но полный fsck корня ДО монтирования — уровень прошивки/initramfs, из пакета недостижим.

## Что делает (в пределах возможного из приложения)
- **Профилактика:** cron `boothealth.sh beat` каждые 5 мин → `sync` + обновление heartbeat. Меньше
  «грязных» данных теряется при пропаже питания.
- **Диагностика:** маркер `/usr/local/.mb-bootstate` (content=clean|running, mtime=последняя живость).
  init.d `boot` на старте: если маркер остался `running` (прошлый стоп не пометил clean) → лог
  «unclean shutdown (last alive ~T)» в `/usr/local/server.main.log`. init.d `stop` пишет `clean`.
- **Восстановление:** если `/` смонтирован ro (ядро после ext4-ошибок) → лог + `mount -o remount,rw /`,
  чтобы железо осталось управляемым (SSH/LuCI), а не «кирпич».

## Тесты / запуск
- `test/unit/boothealth_test.sh` (хук `BH_SOURCED=1`, мок mount/sync/stat, 8 сценариев / 16 ассертов),
  в `make test-unit`. On-device T3 (реальный /proc/mounts, procd boot/stop, ребут) — отложен.
- Деплой: `deploy-vm.sh` ставит скрипт+init.d, `mb-boothealth enable`, инициализирует маркер,
  добавляет cron-строку beat. ipk-путь (`package.sh`, не реализован) должен повторить.

## Сознательно НЕ сделано
- `sync` в rpcd после каждого commit конфига — окно закрывает 5-мин beat; не трогаем уже
  закоммиченный rpcd-слой без отдельных тестов.

## Полная неуязвимость = прошивка (вне пакета)
f2fs или ro-root+overlay; e2fsck в initramfs; аппаратный watchdog RK3328 от фризов (procd уже
пет­ит /dev/watchdog при наличии) — чтобы фриз авто-ребутился, а не требовал ручного hard-reset.
