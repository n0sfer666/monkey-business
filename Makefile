IMAGE := monkey-business-test
INTEG := monkey-business-integ
ROOT  := $(shell pwd)
RUN   := docker run --rm -v $(ROOT):/w -w /w $(IMAGE)

.PHONY: help test-build check lint test-unit test-integ test package dev-up dev-provision dev-console dev-status dev-ssh dev-down dev-deploy clean

help:
	@echo "monkey-business — targets:"
	@echo "  make check       ucode syntax check (types-эквивалент)"
	@echo "  make lint        shellcheck + ucode syntax + eslint"
	@echo "  make test-unit   ucode unit/snapshot tests (в контейнере)"
	@echo "  make test-integ  netns integration (Linux/привилегированный контейнер)"
	@echo "  make test        lint + check + test-unit"
	@echo "  make package     сборка ipk (нужен OpenWrt SDK)"
	@echo "  make dev-up        запуск dev-VM в QEMU фоном (нужен qemu)"
	@echo "  make dev-provision автонастройка VM: сеть+пароль+LuCI (один раз)"
	@echo "  make dev-ssh       ssh в dev-VM (root@localhost:2222, пароль root)"
	@echo "  make dev-console   подключиться к консоли VM (выход Ctrl-C)"
	@echo "  make dev-status    статус VM"
	@echo "  make dev-deploy    разложить проект по путям в dev-VM + restart rpcd"

test-build:
	@docker build -q -t $(IMAGE) -f Dockerfile.test . >/dev/null

check: test-build
	@$(RUN) sh scripts/check-syntax.sh

lint: test-build
	@$(RUN) sh scripts/lint.sh

test-unit: test-build
	@$(RUN) sh test/run-unit.sh

test-integ:
	@docker build -q -t $(INTEG) -f Dockerfile.integ . >/dev/null
	@docker run --rm --privileged -v $(ROOT):/w -w /w $(INTEG) sh test/integ/run.sh

test: lint check test-unit

package:
	@sh scripts/package.sh

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
	@sh scripts/deploy-vm.sh

clean:
	@docker rmi -f $(IMAGE) >/dev/null 2>&1 || true
