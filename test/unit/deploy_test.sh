#!/bin/sh
# Юнит-тест scripts/deploy.sh (device-обёртка над deploy-vm.sh): guard на MB_HOST, порядок
# checks->deploy, проброс host/port, пропуск проверок, abort при провале проверок.
# Реальные команды подменяются стабами через MB_CHECK_CMD/MB_DEPLOY_CMD — без Docker/SSH.
set -u

SELF_DIR=$(dirname "$0")
ROOT="$SELF_DIR/../.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

mkstub() { printf '#!/bin/sh\n%s\n' "$2" > "$1"; chmod +x "$1"; }
mkstub "$T/check"     "echo check >> \"$T/order\""
mkstub "$T/deploy"    "echo \"deploy host=\$MB_VM_SSH_HOST port=\$MB_VM_SSH_PORT\" >> \"$T/order\""
mkstub "$T/failcheck" "echo check >> \"$T/order\"; exit 1"

dep() { ( cd "$ROOT" && env "$@" sh scripts/deploy.sh >/dev/null 2>&1 ); }

PASS=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL $1: want[$3] got[$2]"; fi; }

C="MB_CHECK_CMD=$T/check"; D="MB_DEPLOY_CMD=$T/deploy"

# 1. без MB_HOST -> exit 2, деплой не запущен.
: > "$T/order"
dep "$C" "$D"; rc=$?
eq "nohost.rc" "$rc" 2
eq "nohost.norun" "$(cat "$T/order" 2>/dev/null)" ""

# 2. host + skip checks -> только deploy, порт по умолчанию 22.
: > "$T/order"
dep MB_HOST=root@1.2.3.4 MB_SKIP_CHECKS=1 "$C" "$D"; rc=$?
eq "skip.rc" "$rc" 0
eq "skip.order" "$(cat "$T/order")" "deploy host=root@1.2.3.4 port=22"

# 3. host без skip -> checks ПЕРЕД deploy.
: > "$T/order"
dep MB_HOST=root@1.2.3.4 "$C" "$D"
eq "full.order" "$(tr '\n' ',' < "$T/order")" "check,deploy host=root@1.2.3.4 port=22,"

# 4. провал проверок -> deploy НЕ запускается (set -e abort).
: > "$T/order"
dep MB_HOST=root@1.2.3.4 "MB_CHECK_CMD=$T/failcheck" "$D"; rc=$?
eq "failcheck.rc_nonzero" "$([ "$rc" -ne 0 ] && echo y || echo n)" y
eq "failcheck.no_deploy" "$(cat "$T/order")" "check"

# 5. MB_PORT override пробрасывается.
: > "$T/order"
dep MB_HOST=root@1.2.3.4 MB_SKIP_CHECKS=1 MB_PORT=2222 "$C" "$D"
eq "port.override" "$(cat "$T/order")" "deploy host=root@1.2.3.4 port=2222"

printf '\ndeploy_test: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
