// Разбор URI и query-строк (без внешних модулей — host-тестируемо).
// ucode использует POSIX ERE (нет (?:...), \d, lookahead) — парсим строковыми операциями.

const HEX = "0123456789abcdef";

function hexval(ch) {
	let i = index(HEX, lc(ch));
	return (i >= 0) ? i : null;
}

// Процентное декодирование (%XX). Не трогает '+'.
function urldecode(s) {
	if (s == null)
		return s;
	let out = "";
	let i = 0;
	let n = length(s);
	while (i < n) {
		let c = substr(s, i, 1);
		if (c == "%" && (i + 2) < n) {
			let hi = hexval(substr(s, i + 1, 1));
			let lo = hexval(substr(s, i + 2, 1));
			if (hi != null && lo != null) {
				out += chr(hi * 16 + lo);
				i += 3;
				continue;
			}
		}
		out += c;
		i++;
	}
	return out;
}

// "a=1&b=hello%20world&flag" -> { a: "1", b: "hello world", flag: "" }
function parseQuery(qs) {
	let res = {};
	if (qs == null || qs == "")
		return res;
	for (let pair in split(qs, "&")) {
		if (pair == "")
			continue;
		let eq = index(pair, "=");
		let key, val;
		if (eq < 0) {
			key = pair;
			val = "";
		} else {
			key = substr(pair, 0, eq);
			val = substr(pair, eq + 1);
		}
		val = replace(val, "+", " ");
		res[urldecode(key)] = urldecode(val);
	}
	return res;
}

function lastIndexOf(s, ch) {
	let pos = -1;
	let i = 0;
	let n = length(s);
	while (i < n) {
		if (substr(s, i, 1) == ch)
			pos = i;
		i++;
	}
	return pos;
}

// Разбор URI вида scheme://[user@]host[:port][/path][?query][#fragment].
// Host в скобках [..] трактуется как IPv6. Возвращает null при несовпадении.
function parseUri(uri) {
	if (type(uri) != "string")
		return null;
	let s = trim(uri);
	let sp = index(s, "://");
	if (sp < 0)
		return null;
	let scheme = substr(s, 0, sp);
	if (match(scheme, /^[A-Za-z][A-Za-z0-9+.-]*$/) == null)
		return null;
	let rest = substr(s, sp + 3);
	if (rest == "")
		return null;

	let frag = null;
	let h = index(rest, "#");
	if (h >= 0) {
		frag = substr(rest, h + 1);
		rest = substr(rest, 0, h);
	}

	let query = "";
	let q = index(rest, "?");
	if (q >= 0) {
		query = substr(rest, q + 1);
		rest = substr(rest, 0, q);
	}

	let slash = index(rest, "/");
	if (slash >= 0)
		rest = substr(rest, 0, slash);

	let user = null;
	let at = index(rest, "@");
	if (at >= 0) {
		user = substr(rest, 0, at);
		rest = substr(rest, at + 1);
	}

	let host = null;
	let port = null;
	if (substr(rest, 0, 1) == "[") {
		let close = index(rest, "]");
		if (close < 0)
			return null;
		host = substr(rest, 1, close - 1);
		let after = substr(rest, close + 1);
		if (substr(after, 0, 1) == ":") {
			let ps = substr(after, 1);
			if (ps != "" && match(ps, /^[0-9]+$/) != null)
				port = int(ps);
		}
	} else {
		let colon = lastIndexOf(rest, ":");
		if (colon >= 0) {
			let ps = substr(rest, colon + 1);
			if (ps != "" && match(ps, /^[0-9]+$/) != null) {
				port = int(ps);
				host = substr(rest, 0, colon);
			} else {
				host = rest;
			}
		} else {
			host = rest;
		}
	}

	if (host == null || host == "")
		return null;

	return {
		scheme: lc(scheme),
		user: user,
		host: host,
		port: port,
		query: parseQuery(query),
		fragment: (frag != null) ? urldecode(frag) : null,
	};
}

export { urldecode, parseQuery, parseUri, lastIndexOf };
