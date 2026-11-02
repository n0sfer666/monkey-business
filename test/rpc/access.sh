#!/bin/sh
# Native OpenWrt rpcd/uhttpd against synthetic users and configuration only.
set -eu
work=$(mktemp -d)
pids=''
cleanup() {
	rc=$?
	if [ "$rc" != 0 ]; then cat "$work/rpcd.log" "$work/http.log" 2>/dev/null || true; fi
	for pid in $pids; do kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
	rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' INT TERM
mkdir -p /var/run/ubus /etc/config /usr/share/rpcd/ucode/lib /usr/share/rpcd/acl.d
ln -s /w/src /usr/share/rpcd/ucode/lib/monkey-business
cp /w/root/usr/share/rpcd/ucode/monkey-business.uc /usr/share/rpcd/ucode/
cp /w/luci/root/usr/share/rpcd/acl.d/luci-app-monkey-business.json /usr/share/rpcd/acl.d/
cat > /usr/share/rpcd/acl.d/unauthenticated.json <<'JSON'
{"unauthenticated":{"description":"Synthetic login transport","read":{"ubus":{"session":["login","access"]}}}}
JSON
cat > /usr/share/rpcd/acl.d/mb-test-transport.json <<'JSON'
{"mb-test-transport":{"description":"UCI transport, without configuration access","read":{"ubus":{"uci":["get"]}}}}
JSON
cat > /etc/config/monkey-business <<'UCI'
config global 'global'
 option enabled '0'
 option routing_mode 'global'
 option local_region 'other'
config server 'fixture'
 option tag 'synthetic'
 option address '1.1.1.1'
 option port '443'
 option uuid '11111111-2222-3333-4444-555555555555'
 option source 'manual'
UCI
cat > /etc/config/rpcd <<'UCI'
config login 'reader'
 option username 'mb-reader'
 option password '$1$mbtest$LDJ9xW1Fx8yeGV4tEeq4b/'
 list read 'luci-app-monkey-business'
 list read 'mb-test-transport'
config login 'writer'
 option username 'mb-writer'
 option password '$1$mbtest$LDJ9xW1Fx8yeGV4tEeq4b/'
 list read 'luci-app-monkey-business'
 list read 'mb-test-transport'
 list write 'luci-app-monkey-business'
UCI
chmod 600 /etc/config/monkey-business /etc/config/rpcd
ubusd -s "$work/ubus.sock" > "$work/ubus.log" 2>&1 &
pids="$pids $!"
i=0
while [ ! -S "$work/ubus.sock" ]; do i=$((i+1)); [ "$i" -lt 10 ] || exit 1; sleep 1; done
rpcd -s "$work/ubus.sock" > "$work/rpcd.log" 2>&1 &
pids="$pids $!"
uhttpd -f -p 127.0.0.1:18888 -h "$work" -u /ubus -U "$work/ubus.sock" -t 5 -T 5 > "$work/http.log" 2>&1 &
pids="$pids $!"
i=0
until ubus -s "$work/ubus.sock" -t 1 list monkey-business 2>/dev/null | grep -q monkey-business; do
	i=$((i+1)); [ "$i" -lt 10 ] || { cat "$work/rpcd.log"; exit 1; }; sleep 1
done
apk info -v rpcd ucode ucode-mod-uci 2>/dev/null | head -8
MB_RPC_WORK="$work" ucode /w/test/rpc/access.uc
