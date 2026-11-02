IMAGE := monkey-business-test
INTEG := monkey-business-integ
ROOT  := $(shell pwd)
RUN   := docker run --rm --label monkey-business.check=1 -v $(ROOT):/w -w /w $(IMAGE) timeout 180

.PHONY: help test-image test-build check lint fmt test-unit test-integ test-rpc test-native prepare-native test package deploy dev dev-console dev-status dev-ssh dev-down dev-test-split ui-diff clean

help:
	@echo "monkey-business — targets:"
	@echo "  make check       ucode syntax check (types-эквивалент)"
	@echo "  make lint        shellcheck + ucode syntax + eslint"
	@echo "  make fmt         eslint --fix + prettier --write по JS (нужен npm ci)"
	@echo "  make test-unit   ucode unit/snapshot tests (в контейнере)"
	@echo "  make test-integ  netns integration (Linux/привилегированный контейнер)"
	@echo "  make test        lint + check + test-unit"
	@echo "  make test-build  пересобрать образ проверок (обновить alpine:edge; нужна сеть)"
	@echo "  make package     сборка ipk (нужен OpenWrt SDK)"
	@echo "  make deploy HOST=root@<ip>  залить/обновить на устройство (lint+check+test перед заливкой)"
	@echo "  make dev           поднять стенд одной командой: VM + provision + geo из кэша + deploy + подписка (что уже сделано — пропускает)"
	@echo "  make dev FIXTURE=1 то же + засев вариантов: вторая подписка, off, ручной, недоступный, hysteria2"
	@echo "  make dev-down      остановить VM и сбросить её (кроме кэша образа и geo); следующий make dev — с чистого диска"
	@echo "  make dev-ssh       ssh в dev-VM (root@localhost:2222, пароль root)"
	@echo "  make dev-console   подключиться к консоли VM (выход Ctrl-C)"
	@echo "  make dev-status    статус VM"
	@echo "  make dev-test-split [d=domain]  проверить сплит: выходной IP/страна через SOCKS"
	@echo "  make ui-diff [SCREEN=servers] [WIDTH=1280]  сверка стенда с макетом: pixel diff + замер элементов (А.2), отчёт в .context/investigations/ui-diff/"

# Проверки идут на образе с диска: сборка только если его нет или Dockerfile новее (docker-image.sh).
test-image:
	@sh scripts/docker-image.sh $(IMAGE) Dockerfile.test

# Явно обновить образ (свежий alpine:edge) — единственная цель, которой нужна сеть.
test-build:
	@MB_REBUILD_IMAGE=1 sh scripts/docker-image.sh $(IMAGE) Dockerfile.test

check: test-image
	@$(RUN) sh scripts/check-syntax.sh

lint: test-image
	@$(RUN) sh scripts/lint.sh

fmt: test-image
	@$(RUN) sh scripts/js-style.sh --fix

test-unit: test-image
	@$(RUN) sh test/run-unit.sh

test-integ:
	@sh scripts/docker-image.sh $(INTEG) Dockerfile.integ
	@docker run --rm --label monkey-business.check=1 --privileged -v $(ROOT):/w -w /w $(INTEG) timeout 180 sh test/integ/run.sh

test-rpc:
	@python3 scripts/test-rpc.py

prepare-native:
	@python3 scripts/prepare-native-assets.py

test-native:
	@python3 scripts/test-native-stack.py

test: lint check test-unit

package:
	@sh scripts/package.sh

deploy:
	@MB_HOST=$(HOST) sh scripts/deploy.sh

FIXTURE ?= 0

dev:
	@MB_FIXTURE=$(FIXTURE) sh scripts/dev-env.sh

dev-ssh:
	@sh scripts/dev-vm.sh ssh

dev-console:
	@sh scripts/dev-vm.sh console

dev-status:
	@sh scripts/dev-vm.sh status

dev-down:
	@sh scripts/dev-vm.sh down

dev-test-split:
	@MB_VM_SSH_PASS=root sh scripts/test-split.sh $(d)

SCREEN ?=
WIDTH ?=

ui-diff:
	@NODE_PATH=$$(npm root -g) node scripts/ui-diff/run.js --screen "$(SCREEN)" --width "$(WIDTH)"

clean:
	@docker rmi -f $(IMAGE) $(INTEG) >/dev/null 2>&1 || true
	@rm -rf .make
