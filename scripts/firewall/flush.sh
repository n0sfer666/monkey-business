#!/bin/sh
# Снятие TPROXY-правил (например, при выключении или kill-switch off).
set -u

MARK="${MB_FWMARK:-1}"
TABLE="${MB_RT_TABLE:-100}"

nft delete table inet monkey_business 2>/dev/null || true
ip rule del fwmark "$MARK" lookup "$TABLE" 2>/dev/null || true
ip route flush table "$TABLE" 2>/dev/null || true

echo "tproxy firewall flushed"
