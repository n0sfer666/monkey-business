// Аутбаунд `proxy` и его stream-настройки: единственное место, где конфиг знает о протоколе
// конкретного сервера. Всё остальное (маршрутизация, DNS, инбаунды) работает с тегами.

import { isTrue } from "../lib/val.uc";
import { isHysteria, hysteriaOutbound } from "./hysteria.uc";

function buildStreamSettings(s, opts) {
	opts = opts || {};
	let ss = { network: s.transport.type };
	let t = s.transport;
	if (t.type == "xhttp") {
		ss.xhttpSettings = { path: t.path, host: t.host, mode: t.mode };
		if (isTrue(opts.xhttpPadding))
			ss.xhttpSettings.xPaddingBytes = "100-1000";
	}
	else if (t.type == "ws")
		ss.wsSettings = { path: t.path, headers: { Host: t.host } };
	else if (t.type == "httpupgrade")
		ss.httpupgradeSettings = { path: t.path, host: t.host };
	else if (t.type == "grpc")
		ss.grpcSettings = { serviceName: t.serviceName };

	if (s.security == "reality") {
		ss.security = "reality";
		ss.realitySettings = {
			serverName: s.sni,
			fingerprint: s.fingerprint,
			publicKey: s.reality.publicKey,
			shortId: s.reality.shortId,
			spiderX: s.reality.spiderX,
		};
	} else if (s.security == "tls") {
		ss.security = "tls";
		ss.tlsSettings = { serverName: s.sni, fingerprint: s.fingerprint, alpn: s.alpn };
	} else {
		ss.security = "none";
	}
	return ss;
}

function buildProxyOutbound(s, opts) {
	// hysteria2 живёт отдельным процессом со своим SOCKS: аутбаунд смотрит в него, а не в сервер.
	if (isHysteria(s))
		return hysteriaOutbound(opts);
	let user = { id: s.uuid, encryption: s.encryption };
	if (s.flow != null && s.flow != "")
		user.flow = s.flow;
	return {
		tag: "proxy",
		protocol: "vless",
		settings: { vnext: [{ address: s.address, port: s.port, users: [user] }] },
		streamSettings: buildStreamSettings(s, opts),
	};
}

export { buildStreamSettings, buildProxyOutbound };
