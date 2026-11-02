#!/bin/sh
# Remove only our interception table. An absent table is an idempotent success.
set -eu
MARK="${MB_FWMARK:-1}"
TABLE="${MB_RT_TABLE:-100}"
case "$MARK:$TABLE" in *[!0-9:]*) exit 1 ;; esac
tables=$(nft list tables) || exit 1
if printf '%s\n' "$tables" | grep -qx 'table inet monkey_business'; then
 nft delete table inet monkey_business || exit 1
fi
# A failed deletion must never be hidden by the logger in the init script.
tables=$(nft list tables) || exit 1
if printf '%s\n' "$tables" | grep -qx 'table inet monkey_business'; then exit 1; fi
rules=$(ip -4 rule show) || exit 1
if printf '%s\n' "$rules" | grep -Eq "fwmark (0x0*$MARK|$MARK) lookup $TABLE( |$)"; then
 ip -4 rule del fwmark "$MARK" lookup "$TABLE" || exit 1
fi
ip -4 route flush table "$TABLE" || exit 1
echo "tproxy firewall flushed"
