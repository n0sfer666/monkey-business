#!/bin/sh
# A reachable direct target must not turn a broken candidate into a success.
set -eu
work=$(mktemp -d)
xpid=''
hpid=''
cleanup() {
	[ -z "$xpid" ] || { kill "$xpid" 2>/dev/null || true; wait "$xpid" 2>/dev/null || true; }
	[ -z "$hpid" ] || { kill "$hpid" 2>/dev/null || true; wait "$hpid" 2>/dev/null || true; }
	rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 1' INT TERM
cat > "$work/respond" <<'HTTP'
#!/bin/sh
printf 'HTTP/1.1 200 OK\r\nContent-Length: 12\r\nConnection: close\r\n\r\ndirect-only\n'
HTTP
chmod 700 "$work/respond"
nc -lk -s 127.0.0.1 -p 18081 -e "$work/respond" &
hpid=$!
cat > "$work/generate.uc" <<'UEOF'
import { generateProbe } from '/w/src/generator/xray.uc';
print(sprintf('%J', generateProbe({
	server: { protocol: 'vless', address: '127.0.0.1', port: 1,
		uuid: '11111111-2222-3333-4444-555555555555', encryption: 'none', security: 'none',
		transport: { type: 'tcp' } },
	global: { local_region: 'other', ipv6_block: '0' },
	dns: { direct_dns: '127.0.0.1' }, probe_port: 18082
})));
UEOF
ucode "$work/generate.uc" > "$work/xray.json"
xray run -c "$work/xray.json" > "$work/xray.log" 2>&1 &
xpid=$!
# Bounded readiness; a successful SOCKS handshake is not a successful VPN probe.
i=0
until curl --noproxy '*' -fsS --max-time 1 http://127.0.0.1:18081/ > "$work/body" 2>/dev/null; do
	i=$((i + 1)); [ "$i" -lt 20 ] || exit 1
	sleep 0.1
done
[ "$(cat "$work/body")" = direct-only ]
i=0
until nc -z 127.0.0.1 18082 2>/dev/null; do
	kill -0 "$xpid" || { cat "$work/xray.log"; exit 1; }
	i=$((i + 1)); [ "$i" -lt 20 ] || exit 1
	sleep 0.1
done
if curl --noproxy '' --socks5 127.0.0.1:18082 --max-time 2 -fsS http://127.0.0.1:18081/ > /dev/null 2>&1; then
	echo 'FAIL: diagnostic traffic escaped through direct_dns'
	exit 1
fi
echo 'PASS: direct target reachable, broken candidate cannot escape via direct_dns'
