#!/bin/sh
# Валидация сгенерированного конфига РЕАЛЬНЫМ xray (-test).
# Ловит расхождения генератора со схемой Xray. Использует валидный x25519 publicKey
# и hex shortId (иначе xray отвергнет reality по типам, а не по структуре).
# Кейсы: bypass-local (ru) и passthrough (local_region=other).
set -u

PUB=$(xray x25519 | grep -i 'public' | awk '{print $NF}')
[ -n "$PUB" ] || { echo "FAIL: no x25519 pubkey"; exit 1; }

gen() { # gen <global-json> <out>
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
	global: $1,
	server: server,
	anti_dpi: { xhttp_padding: "1" },
	dns: { mode: "split", direct_dns: "223.5.5.5", doh_url: "https://1.1.1.1/dns-query" }
};
writefile("$2", sprintf("%J", generate(cfg)));
UEOF
	ucode /tmp/gen.uc || { echo "FAIL: config generation ($2)"; exit 1; }
}

validate() { # validate <file> <label>
	if xray -test -config "$1" 2>/tmp/xerr || xray run -test -c "$1" 2>>/tmp/xerr; then
		echo "xray accepts $2 config: OK"
		return 0
	fi
	echo "FAIL: xray rejected $2 config"
	cat /tmp/xerr
	exit 1
}

gen '{ tproxy_port: 12345, routing_mode: "bypass-local", local_region: "ru", ipv6_block: "1" }' /tmp/xray.json
validate /tmp/xray.json "bypass-local(ru)"

gen '{ tproxy_port: 12345, routing_mode: "global", local_region: "other", ipv6_block: "1" }' /tmp/xray-other.json
validate /tmp/xray-other.json "passthrough(other)"
