// Парсер подписки VPN: auto-detect формата и нормализация серверов.
//
// Нормализованный server-объект (КОНТРАКТ для генератора, src/generator/xray.uc):
//   {
//     tag, protocol:"vless", address, port, uuid, encryption:"none",
//     flow, security:"reality"|"tls"|"none", sni, fingerprint, alpn:[...],
//     reality: { publicKey, shortId, spiderX } | null,
//     transport: { type, path, host, mode, serviceName },
//     source: "subscription"|"manual"
//   }
//
// parse(raw) -> { format, servers:[...], errors:[...] }

import { parseUri } from "../lib/uri.uc";

function truncate(s, n) {
	n = n || 40;
	return (length(s) > n) ? (substr(s, 0, n) + "...") : s;
}

function commaList(s) {
	let out = [];
	if (s == null || s == "")
		return out;
	for (let p in split(s, ","))
		if (trim(p) != "")
			push(out, trim(p));
	return out;
}

function buildTransport(q) {
	let t = q.type || "tcp";
	let tr = { type: t, path: "", host: "", mode: "", serviceName: "" };
	if (t == "xhttp") {
		tr.path = q.path || "/";
		tr.host = q.host || "";
		tr.mode = q.mode || "auto";
	} else if (t == "ws" || t == "httpupgrade") {
		tr.path = q.path || "/";
		tr.host = q.host || "";
	} else if (t == "grpc") {
		tr.serviceName = q.serviceName || q.path || "";
	}
	return tr;
}

function normalizeVless(u, raw) {
	if (u.user == null || u.user == "")
		return { error: "missing uuid: " + truncate(raw) };
	if (u.port == null || u.port < 1 || u.port > 65535)
		return { error: "invalid port: " + truncate(raw) };

	let q = u.query;
	let security = q.security;
	if (security == null || security == "")
		security = (q.pbk != null && q.pbk != "") ? "reality" : "tls";

	let reality = null;
	if (security == "reality")
		reality = { publicKey: q.pbk || "", shortId: q.sid || "", spiderX: q.spx || "/" };

	let server = {
		tag: (u.fragment != null && u.fragment != "") ? u.fragment : sprintf("%s:%d", u.host, u.port),
		protocol: "vless",
		address: u.host,
		port: u.port,
		uuid: u.user,
		encryption: q.encryption || "none",
		flow: q.flow || "",
		security: security,
		sni: q.sni || q.peer || q.host || u.host,
		fingerprint: q.fp || "chrome",
		alpn: commaList(q.alpn),
		reality: reality,
		transport: buildTransport(q),
		source: "subscription",
	};
	return { server: server };
}

function parseUriList(text) {
	let servers = [];
	let errors = [];
	for (let line in split(text, "\n")) {
		let t = trim(line);
		if (t == "" || substr(t, 0, 1) == "#")
			continue;
		let u = parseUri(t);
		if (u == null) {
			push(errors, "unparseable: " + truncate(t));
			continue;
		}
		if (u.scheme != "vless") {
			push(errors, "unsupported scheme '" + u.scheme + "'");
			continue;
		}
		let r = normalizeVless(u, t);
		if (r.error != null)
			push(errors, r.error);
		else
			push(servers, r.server);
	}
	return { servers: servers, errors: errors };
}

function decodeBase64Maybe(raw) {
	let s = trim(raw);
	s = replace(s, "\n", "");
	s = replace(s, "\r", "");
	s = replace(s, " ", "");
	s = replace(s, "-", "+");
	s = replace(s, "_", "/");
	s = replace(s, "=", "");
	if (s == "" || match(s, /^[A-Za-z0-9+\/]+$/) == null)
		return null;
	let pad = length(s) % 4;
	if (pad == 1)
		return null;
	if (pad == 2)
		s += "==";
	else if (pad == 3)
		s += "=";
	return b64dec(s);
}

function detectFormat(raw) {
	let s = trim(raw);
	if (s == "")
		return "unknown";
	let c0 = substr(s, 0, 1);
	if (c0 == "{" || c0 == "[")
		return "json";
	if (index(s, "proxies:") >= 0)
		return "clash";
	if (index(s, "://") >= 0)
		return "uri-list";
	let dec = decodeBase64Maybe(s);
	if (dec != null && index(dec, "://") >= 0)
		return "base64";
	return "unknown";
}

function parse(raw) {
	if (type(raw) != "string" || trim(raw) == "")
		return { format: "unknown", servers: [], errors: ["empty input"] };

	let fmt = detectFormat(raw);
	if (fmt == "uri-list") {
		let r = parseUriList(raw);
		return { format: fmt, servers: r.servers, errors: r.errors };
	}
	if (fmt == "base64") {
		let r = parseUriList(decodeBase64Maybe(raw));
		return { format: fmt, servers: r.servers, errors: r.errors };
	}
	if (fmt == "clash")
		return { format: fmt, servers: [], errors: ["clash format not yet supported"] };
	if (fmt == "json")
		return { format: fmt, servers: [], errors: ["json format not yet supported"] };
	return { format: "unknown", servers: [], errors: ["unrecognized subscription format"] };
}

export { parse, detectFormat, normalizeVless, parseUriList, decodeBase64Maybe };
