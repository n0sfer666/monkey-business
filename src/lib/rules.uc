const LABEL = /^[a-z0-9_]([a-z0-9_-]{0,61}[a-z0-9_])?$/i;
const TLD = /^([a-z]{2,63}|xn--[a-z0-9-]+)$/i;
const MATCHER = /^(full|domain|keyword|regexp):(.*)$/i;

function ipv4(a) {
	let parts = split(a, ".");
	if (length(parts) != 4)
		return false;
	for (let x in parts)
		if (match(x, /^(0|[1-9][0-9]{0,2})$/) == null || int(x) > 255)
			return false;
	return true;
}

function groups(s) {
	if (s == "")
		return 0;
	let n = 0;
	for (let g in split(s, ":")) {
		if (match(g, /^[0-9a-f]{1,4}$/i) == null)
			return -1;
		n++;
	}
	return n;
}

function ipv6(a) {
	let v4 = match(a, /^(.*:)([0-9.]+)$/);
	if (v4 != null && index(v4[2], ".") >= 0) {
		if (!ipv4(v4[2]))
			return false;
		a = v4[1] + "0:0";
	}
	let halves = split(a, "::");
	if (length(halves) > 2)
		return false;
	if (length(halves) == 1)
		return groups(a) == 8;
	let l = groups(halves[0]), r = groups(halves[1]);
	return l >= 0 && r >= 0 && l + r <= 7;
}

function cidr(addr, valid, max, code) {
	let p = split(addr, "/");
	if (length(p) > 2)
		return { code: "slashes", arg: "" };
	if (!valid(p[0]))
		return { code: code, arg: "" };
	if (length(p) == 2 && (match(p[1], /^[0-9]+$/) == null || int(p[1]) > max))
		return { code: "prefix", arg: "" + max };
	return null;
}

function mappedV4(addr) {
	let b = iptoarr(split(addr, "/")[0]);
	if (length(b) != 16 || join(",", slice(b, 0, 12)) != "0,0,0,0,0,0,0,0,0,0,255,255")
		return null;
	return join(".", slice(b, 12));
}

function domain(t) {
	let d = (substr(t, 0, 2) == "*.") ? substr(t, 2) : t;
	if (index(d, "*") >= 0)
		return { code: "wildcard", arg: "" };
	let labels = split(d, ".");
	for (let l in labels)
		if (l == "")
			return { code: "incomplete", arg: "" };
	if (length(labels) < 2 && !(d != t && match(d, TLD) != null))
		return { code: "not_full", arg: d };
	for (let l in labels)
		if (match(l, LABEL) == null)
			return { code: "chars", arg: "" };
	if (match(labels[length(labels) - 1], TLD) == null)
		return { code: "tld", arg: "" };
	return null;
}

function checkEntry(t) {
	if (match(t, /\s/) != null)
		return { code: "space", arg: "" };
	let url = match(t, /^[a-z][a-z0-9+.-]*:\/\/([^\/]*)/i);
	if (url != null)
		return { code: "scheme", arg: url[1] };
	let geo = match(t, /^(geosite|geoip):(.*)$/i);
	if (geo != null) {
		if (geo[2] == "")
			return { code: "geo_empty", arg: lc(geo[1]) };
		return (match(geo[2], /^[a-z0-9!@._-]+$/i) != null) ? null : { code: "geo_name", arg: lc(geo[1]) };
	}
	let m = match(t, MATCHER);
	if (m != null)
		return (m[2] == "") ? { code: "matcher_empty", arg: lc(m[1]) } : null;
	if (match(t, /^[0-9.\/]+$/) != null)
		return cidr(t, ipv4, 32, "ip4");
	let hp = match(t, /^([^:]+):[0-9]{1,5}$/);
	if (hp != null)
		return { code: "port", arg: hp[1] };
	if (index(t, ":") >= 0) {
		let canon = match(t, /^::ffff:[0-9.]+(\/|$)/i) != null;
		let v4 = canon ? null : mappedV4(t);
		if (v4 != null)
			return { code: "mapped", arg: "::ffff:" + v4 };
		return cidr(t, ipv6, canon ? 32 : 128, "ip6");
	}
	if (index(t, "/") >= 0)
		return { code: "path", arg: split(t, "/")[0] };
	return domain(t);
}

function entries(text) {
	let out = [];
	let n = 0;
	for (let line in split((text != null) ? "" + text : "", "\n")) {
		n++;
		let t = trim(line);
		if (t == "" || substr(t, 0, 1) == "#")
			continue;
		for (let part in split(t, ",")) {
			let v = trim(part);
			if (v != "")
				push(out, { line: n, value: v });
		}
	}
	return out;
}

function listErrors(list, text) {
	let out = [];
	let seen = {};
	for (let e in entries(text)) {
		let err = checkEntry(e.value);
		if (err == null || seen[e.line])
			continue;
		seen[e.line] = true;
		push(out, { list: list, line: e.line, code: err.code, arg: err.arg });
	}
	return out;
}

function validateRules(direct, proxy) {
	let out = listErrors("direct", direct);
	for (let e in listErrors("proxy", proxy))
		push(out, e);
	return out;
}

export { MATCHER, entries, checkEntry, validateRules };
