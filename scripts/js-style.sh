#!/bin/sh
set -u

bin=node_modules/.bin
if [ ! -x "$bin/eslint" ] || [ ! -x "$bin/prettier" ]; then
	echo "js style: no node_modules, run 'npm ci' on the host"
	exit 1
fi

if [ "${1:-}" = "--fix" ]; then
	"$bin/eslint" --fix . && "$bin/prettier" --write --log-level warn .
	exit $?
fi

"$bin/eslint" . && "$bin/prettier" --check --log-level warn . && echo "js style: ok"
