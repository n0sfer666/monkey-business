#!/bin/sh
# Валидация сгенерированного конфига РЕАЛЬНЫМ xray (-test).
# Ловит расхождения генератора со схемой Xray. Использует валидный x25519 publicKey
# и hex shortId (иначе xray отвергнет reality по типам, а не по структуре).
set -u

PUB=$(xray x25519 | grep -i 'public' | awk '{print $NF}')
[ -n "$PUB" ] || { echo "FAIL: no x25519 pubkey"; exit 1; }

cat > /tmp/gen.uc <<UEOF
import { generate } from "/w/src/generator/xray.uc";
import { writefile } from "fs";
let server = {
	tag: "t", protocol: "vless", address: "example.com", port: 443,
	uuid: "11111111-2222-3333-4444-555555555555", encryption: "none", flow: "",
	security: "reality", sni: "www.microsoft.com", fingerprint: "chrome", alpn: [],
	reality: { publicKey: "$PUB", shortId: "0123abcd", spiderX: "/" },
	transport: { type: "xhttp", path: "/x", host: "", mode: "auto", serviceName: "" },
	source: "manual"
};
let cfg = {
	global: { tproxy_port: 12345, routing_mode: "bypass-local", local_region: "ru", ipv6_block: "1" },
	server: server,
	anti_dpi: { xhttp_padding: "1" },
	dns: { direct_dns: "223.5.5.5", doh_url: "https://1.1.1.1/dns-query" }
};
writefile("/tmp/xray.json", sprintf("%J", generate(cfg)));
UEOF

ucode /tmp/gen.uc || { echo "FAIL: config generation"; exit 1; }

if xray -test -config /tmp/xray.json 2>/tmp/xerr; then
	echo "xray accepts generated config: OK"
	exit 0
fi
if xray run -test -c /tmp/xray.json 2>>/tmp/xerr; then
	echo "xray accepts generated config: OK"
	exit 0
fi

echo "FAIL: xray rejected generated config"
cat /tmp/xerr
exit 1
