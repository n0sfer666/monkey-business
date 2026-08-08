IMAGE := monkey-business-test
INTEG := monkey-business-integ
ROOT  := $(shell pwd)
RUN   := docker run --rm -v $(ROOT):/w -w /w $(IMAGE)

.PHONY: help test-image test-build check lint test-unit test-integ test package deploy dev-up dev-provision dev-console dev-status dev-ssh dev-down dev-deploy dev-rebuild dev-test-split clean

help:
	@echo "monkey-business — targets:"
	@echo "  make check       ucode syntax check (types-эквивалент)"
	@echo "  make lint        shellcheck + ucode syntax + eslint"
	@echo "  make test-unit   ucode unit/snapshot tests (в контейнере)"
	@echo "  make test-integ  netns integration (Linux/привилегированный контейнер)"
	@echo "  make test        lint + check + test-unit"
	@echo "  make test-build  пересобрать образ проверок (обновить alpine:edge; нужна сеть)"
	@echo "  make package     сборка ipk (нужен OpenWrt SDK)"
	@echo "  make deploy HOST=root@<ip>  залить/обновить на устройство (lint+check+test перед заливкой)"
	@echo "  make dev-up        запуск dev-VM в QEMU фоном (нужен qemu)"
	@echo "  make dev-provision автонастройка VM: сеть+пароль+LuCI (один раз)"
	@echo "  make dev-ssh       ssh в dev-VM (root@localhost:2222, пароль root)"
	@echo "  make dev-console   подключиться к консоли VM (выход Ctrl-C)"
	@echo "  make dev-status    статус VM"
	@echo "  make dev-deploy    разложить проект по путям в dev-VM + restart rpcd"
	@echo "  make dev-rebuild   ПОЛНОЕ восстановление VM с нуля (если зависла загрузка): clean+up+provision+deploy"
	@echo "  make dev-test-split [d=domain]  проверить сплит: выходной IP/страна через SOCKS"

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

test-unit: test-image
	@$(RUN) sh test/run-unit.sh

test-integ:
	@sh scripts/docker-image.sh $(INTEG) Dockerfile.integ
	@docker run --rm --privileged -v $(ROOT):/w -w /w $(INTEG) sh test/integ/run.sh

test: lint check test-unit

package:
	@sh scripts/package.sh

deploy:
	@MB_HOST=$(HOST) sh scripts/deploy.sh

dev-up:
	@sh scripts/dev-vm.sh up

dev-ssh:
	@sh scripts/dev-vm.sh ssh

dev-provision:
	@sh scripts/dev-vm.sh provision

dev-console:
	@sh scripts/dev-vm.sh console

dev-status:
	@sh scripts/dev-vm.sh status

dev-down:
	@sh scripts/dev-vm.sh down

dev-deploy:
	@MB_VM_SSH_PASS=root MB_UBUS_RESPAWN=1 sh scripts/deploy-vm.sh

dev-rebuild:
	@sh scripts/dev-vm.sh clean
	@$(MAKE) --no-print-directory dev-up
	@$(MAKE) --no-print-directory dev-provision
	@$(MAKE) --no-print-directory dev-deploy
	@echo ">> VM пересобрана начисто. Открой LuCI (:8090, root/root), на вкладке Servers впиши URL подписки."

dev-test-split:
	@MB_VM_SSH_PASS=root sh scripts/test-split.sh $(d)

clean:
	@docker rmi -f $(IMAGE) $(INTEG) >/dev/null 2>&1 || true
	@rm -rf .make
