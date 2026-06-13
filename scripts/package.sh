#!/bin/sh
# Сборка ipk-пакета через OpenWrt SDK (этап дистрибуции).
# Требует распакованный OpenWrt/ImmortalWrt SDK под целевой target (rockchip/armv8).
# Окружение:
#   MB_SDK_DIR — путь к SDK (обязателен)
set -u

SDK_DIR="${MB_SDK_DIR:-}"

if [ -z "$SDK_DIR" ] || [ ! -d "$SDK_DIR" ]; then
	cat >&2 <<'EOF'
[blocked] Нужен OpenWrt/ImmortalWrt SDK.
  1) Скачать SDK под target rockchip/armv8 (ImmortalWrt snapshots).
  2) Распаковать, выставить MB_SDK_DIR=/path/to/sdk
  3) Поместить feed-описание пакета (Makefile OpenWrt) и запустить:
       make package/monkey-business/compile V=s
Готовые .ipk появятся в bin/packages/aarch64*/.
EOF
	exit 1
fi

echo ">> SDK: $SDK_DIR"
echo "[not-implemented] копирование package-feed и вызов make package/... реализуется на этапе дистрибуции" >&2
exit 1
