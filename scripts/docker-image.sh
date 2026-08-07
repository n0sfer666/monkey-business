#!/bin/sh
# Держит локальный образ для проверок и НЕ ходит в сеть без нужды.
#
# `docker build` с плавающим тегом (FROM alpine:edge) дёргает registry на КАЖДЫЙ вызов, даже когда
# готовый образ лежит на диске. Из-за этого недоступный Docker Hub (TLS handshake timeout) ронял
# make lint/check/test-unit, а вместе с ними и `make deploy` — при полностью рабочем окружении.
# Здесь: пересобираем, только если образа нет или Dockerfile новее последней сборки; сборка не
# прошла, а образ на диске есть — работаем на нём.
#
#   sh scripts/docker-image.sh <image> <dockerfile>
#   MB_REBUILD_IMAGE=1 sh scripts/docker-image.sh <image> <dockerfile>   # принудительно (make test-build)
set -eu

IMAGE="${1:?usage: docker-image.sh <image> <dockerfile>}"
FILE="${2:?usage: docker-image.sh <image> <dockerfile>}"
STAMP=".make/${IMAGE}.stamp"

exists() { [ -n "$(docker images -q "$IMAGE" 2>/dev/null)" ]; }

# Штамп, а не время создания образа: сравнивать RFC3339 из docker inspect в POSIX sh нечем.
fresh() {
	exists || return 1
	[ -f "$STAMP" ] || return 1
	[ -z "$(find "$FILE" -newer "$STAMP" 2>/dev/null)" ]
}

build() {
	mkdir -p "$(dirname "$STAMP")"
	docker build -q -t "$IMAGE" -f "$FILE" . >/dev/null || return 1
	touch "$STAMP"
}

if [ "${MB_REBUILD_IMAGE:-0}" = 1 ]; then
	build || { echo "!! пересборка $IMAGE не прошла: нет сети до Docker Hub или не запущен Docker" >&2; exit 1; }
	exit 0
fi

fresh && exit 0

build && exit 0

if exists; then
	echo ">> docker build не прошёл (Docker Hub недоступен?) — беру образ $IMAGE с диска" >&2
	exit 0
fi

cat >&2 <<EOF
!! Образ $IMAGE не собран, локальной копии нет.
   Обычно это недоступный Docker Hub (registry-1.docker.io) или незапущенный Docker.
   Дальше: поднять сеть/VPN и повторить, либо залить без проверок —
     MB_SKIP_CHECKS=1 make deploy HOST=root@<ip>
EOF
exit 1
