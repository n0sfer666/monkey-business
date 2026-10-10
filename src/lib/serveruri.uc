const STRICT = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
const SAFE = STRICT + "/,:";

function urlencode(s, safe) {
	let keep = safe || SAFE;
	let out = "";
	let text = "" + s;
	for (let i = 0; i < length(text); i++) {
		let c = substr(text, i, 1);
		out += (index(keep, c) >= 0) ? c : sprintf("%%%02X", ord(text, i));
	}
	return out;
}

function str(v) {
	return (v != null) ? "" + v : "";
}

function hostPort(s) {
	let host = str(s.address);
	if (index(host, ":") >= 0)
		host = "[" + host + "]";
	return host + ":" + s.port;
}

function query(pairs) {
	let out = [];
	for (let p in pairs)
		if (p[2] || str(p[1]) != "")
			push(out, p[0] + "=" + urlencode(str(p[1])));
	return length(out) ? "?" + join("&", out) : "";
}

function transportPairs(tr) {
	let t = (tr != null && str(tr.type) != "") ? tr.type : "tcp";
	let out = [ [ "type", t, true ] ];
	if (t == "xhttp")
		push(out, [ "path", tr.path ], [ "host", tr.host ], [ "mode", tr.mode ]);
	else if (t == "ws" || t == "httpupgrade")
		push(out, [ "path", tr.path ], [ "host", tr.host ]);
	else if (t == "grpc")
		push(out, [ "serviceName", tr.serviceName ]);
	return out;
}

function vlessUri(s) {
	let pairs = [
		[ "security", s.security || "tls", true ],
		[ "encryption", s.encryption || "none", true ],
		[ "flow", s.flow ],
		[ "sni", s.sni ],
		[ "fp", s.fingerprint ],
		[ "alpn", (type(s.alpn) == "array") ? join(",", s.alpn) : s.alpn ],
	];
	if (s.security == "reality" && type(s.reality) == "object")
		push(pairs, [ "pbk", s.reality.publicKey ], [ "sid", s.reality.shortId ], [ "spx", s.reality.spiderX ]);
	for (let p in transportPairs(s.transport))
		push(pairs, p);
	return "vless://" + str(s.uuid) + "@" + hostPort(s) + query(pairs);
}

function hysteriaUri(s) {
	let obfs = (type(s.obfs) == "object") ? s.obfs : {};
	let pairs = [
		[ "sni", s.sni ],
		[ "insecure", (str(s.insecure) == "1") ? "1" : "" ],
		[ "obfs", obfs.type ],
		[ "obfs-password", obfs.password ],
		[ "pinSHA256", s.pin_sha256 ],
		[ "mport", s.mport ],
	];
	return "hysteria2://" + urlencode(str(s.password), STRICT) + "@" + hostPort(s) + "/" + query(pairs);
}

function serverToUri(s) {
	let base = (s.protocol == "hysteria2") ? hysteriaUri(s) : vlessUri(s);
	return base + "#" + urlencode(str(s.tag));
}

export { serverToUri, urlencode };
