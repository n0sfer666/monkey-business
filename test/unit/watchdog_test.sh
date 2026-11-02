#!/bin/sh
# Stale cron entry is read-only; no sourced state and no competing health loop.
set -eu
script=root/usr/share/monkey-business/watchdog.sh
# shellcheck disable=SC2016
if grep -q '\. "\$STATE"' "$script"; then exit 1; fi
grep -q '^exec /etc/init.d/monkey-business-observer running$' "$script"
if grep -q 'WD_LINE=' scripts/deploy-vm.sh; then exit 1; fi
grep -q 'monkey-business-observer enable' scripts/deploy-vm.sh
echo 'watchdog_test: compatibility path never starts probes or evaluates state'
