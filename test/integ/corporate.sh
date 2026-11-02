#!/bin/sh
# Real packet checks for exact/wildcard priority and proxy fail-closed with KILL=0.
set -eu
work=$(mktemp -d)
pids=''
cleanup() {
	for pid in $pids; do kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; done
	for ns in mbcorp-r mbcorp-c mbcorp-s; do ip netns del "$ns" 2>/dev/null || true; done
	rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' INT TERM
for ns in mbcorp-r mbcorp-c mbcorp-s; do ip netns add "$ns"; ip -n "$ns" link set lo up; done
ip link add cr type veth peer name cc
ip link set cr netns mbcorp-r; ip link set cc netns mbcorp-c
ip link add sr type veth peer name ss
ip link set sr netns mbcorp-r; ip link set ss netns mbcorp-s
ip -n mbcorp-r addr add 10.0.0.1/24 dev cr
ip -n mbcorp-c addr add 10.0.0.2/24 dev cc
ip -n mbcorp-r addr add 8.8.8.1/24 dev sr
ip -n mbcorp-s addr add 8.8.8.8/24 dev ss
ip -n mbcorp-r link set cr up; ip -n mbcorp-r link set sr up
ip -n mbcorp-c link set cc up; ip -n mbcorp-s link set ss up
ip -n mbcorp-c route add default via 10.0.0.1
ip -n mbcorp-s route add default via 8.8.8.1
ip netns exec mbcorp-r sysctl -wq net.ipv4.ip_forward=1
cat > "$work/respond" <<'HTTP'
#!/bin/sh
printf 'HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nok\n'
HTTP
chmod 700 "$work/respond"
for port in 18081 18082 53; do
	ip netns exec mbcorp-s nc -lk -s 8.8.8.8 -p "$port" -e "$work/respond" &
	pids="$pids $!"
done
# Use the same production generator as the runtime; no raw user values enter nft.
cat > "$work/gen.uc" <<'UEOF'
import { declarations } from '/w/src/generator/corporate-nft.uc';
let rules = [
 { id: 'wild', name: 'wild', address: '8.8.8.8', enabled: 1, port: '' },
 { id: 'exact', name: 'exact', address: '8.8.8.8', enabled: 0, port: '18081' }
];
print(declarations(rules, { wild: { route: 'proxy' } }));
UEOF
ucode "$work/gen.uc" > "$work/sets.nft"
chmod 600 "$work/sets.nft"
ip netns exec mbcorp-r env MB_LAN_IFACE=cr MB_KILL_SWITCH=0 MB_DIRECT_BYPASS=0 \
	MB_CORPORATE_SETS="$work/sets.nft" sh scripts/firewall/apply.sh >/dev/null
fetch() { ip netns exec mbcorp-c curl --noproxy '*' -fsS --max-time 1 "http://8.8.8.8:$1/" 2>/dev/null; }
i=0
until [ "$(fetch 18081)" = ok ]; do
	i=$((i + 1)); [ "$i" -lt 5 ] || { echo 'FAIL: exact direct lost to wildcard proxy'; exit 1; }
done
if fetch 18082; then echo 'FAIL: wildcard proxy leaked direct with KILL=0'; exit 1; fi
if fetch 53; then echo 'FAIL: corporate :53 leaked or redirected'; exit 1; fi
# A malformed transaction cannot replace working policy or empty its exact set.
printf 'flush set inet monkey_business corp_exact_direct\nthis is invalid\n' > "$work/bad.nft"
if ip netns exec mbcorp-r nft -f "$work/bad.nft" 2>/dev/null; then exit 1; fi
[ "$(fetch 18081)" = ok ] || { echo 'FAIL: failed nft transaction changed policy'; exit 1; }
echo 'PASS: exact direct, wildcard proxy, :53, KILL=0 and nft rollback packet checks'
