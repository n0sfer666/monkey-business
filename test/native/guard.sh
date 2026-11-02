#!/bin/sh
# Synthetic first-packet attack against the actual production guard and Hysteria.
set -eu
pids=''
cleanup() { for p in $pids; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done; }
trap cleanup EXIT
trap 'exit 1' INT TERM
wget -q -T 10 -O /tmp/mb-relay-client http://10.0.2.2:18981/relay-client
wget -q -T 10 -O /tmp/mb-fixture-key.pem http://10.0.2.2:18981/fixture-key.pem
chmod 700 /tmp/mb-relay-client
umask 077
cat > /tmp/mb-guard-server.json <<'JSON'
{"listen":"127.0.0.1:14444","tls":{"cert":"/tmp/mb-fixture-ca.pem","key":"/tmp/mb-fixture-key.pem"},"auth":{"type":"password","password":"synthetic"}}
JSON
cat > /tmp/mb-guard-client.json <<'JSON'
{"server":"127.0.0.1:14444","auth":"synthetic","tls":{"sni":"one.fixture.example","insecure":true},"lazy":true,"fastOpen":true,"socks5":{"listen":"127.0.0.1:12001","username":"synthetic","password":"synthetic"}}
JSON
hysteria server -c /tmp/mb-guard-server.json >/tmp/mb-guard-server.log 2>&1 &
pids="$pids $!"
/usr/share/monkey-business/engine-run.sh /usr/bin/hysteria client -c /tmp/mb-guard-client.json >/tmp/mb-guard-client.log 2>&1 &
pids="$pids $!"
/tmp/mb-relay-client
nft list chain inet monkey_business_diagnostics input
