// Маппинг server-контракта в опции UCI и обратно.
//
// В памяти сервер держит вложенные transport/reality/obfs и массив alpn, а в UCI они лежат ПЛОСКО
// (tr_type, pbk, obfs_type, ...): форма LuCI редактирует ровно опции UCI и вложенный JSON править
// не умеет. Прежняя схема писала эти поля JSON-строкой, поэтому revive понимает оба формата —
// на устройстве уже лежат серверы старой раскладки, и до первого обновления подписки они обязаны
// работать как раньше.

// Блоб прежней схемы правится руками в /etc/config: битый JSON тут уронил бы чтение списка, а с ним
// и все ubus-методы -> safeJson. Испорченный блоб = блоба нет, поля возьмутся из плоских опций.
import { safeJson } from "./val.uc";

// Имена плоских опций дублирует таблица LEGACY в luci/.../serveropt.js (форма достаёт из прежнего
// блоба то же самое) — менять эти три карты и её нужно вместе.
const TRANSPORT = { tr_type: "type", tr_path: "path", tr_host: "host", tr_mode: "mode", tr_service: "serviceName" };
const REALITY = { pbk: "publicKey", sid: "shortId", spx: "spiderX" };
const OBFS = { obfs_type: "type", obfs_password: "password" };

function str(v) {
	return (v != null) ? "" + v : "";
}

function fromFlat(s, map_) {
	let out = {};
	let empty = true;
	for (let flat in map_) {
		out[map_[flat]] = str(s[flat]);
		if (out[map_[flat]] != "")
			empty = false;
	}
	return empty ? null : out;
}

function toFlat(s, obj, map_) {
	for (let flat in map_)
		s[flat] = (obj != null) ? str(obj[map_[flat]]) : "";
}

function reviveTransport(s) {
	if (type(s.transport) == "object")
		return s.transport;
	if (type(s.transport) == "string" && s.transport != "" && s.transport != "null") {
		let old = safeJson(s.transport);
		if (type(old) == "object")
			return old;
	}
	let tr = fromFlat(s, TRANSPORT) || {};
	return {
		type: (tr.type != null && tr.type != "") ? tr.type : "tcp",
		path: str(tr.path), host: str(tr.host), mode: str(tr.mode), serviceName: str(tr.serviceName),
	};
}

function reviveAlpn(s) {
	let v = s.alpn;
	if (type(v) == "array")
		return v;
	if (type(v) != "string" || trim(v) == "")
		return [];
	// Прежняя схема писала массив как JSON. Значения ALPN ("h2", "http/1.1") с "[" не начинаются,
	// так что первый символ различает форматы однозначно.
	if (substr(trim(v), 0, 1) == "[") {
		let old = safeJson(v);
		return (type(old) == "array") ? old : [];
	}
	let out = [];
	for (let p in split(v, ","))
		if (trim(p) != "")
			push(out, trim(p));
	return out;
}

function reviveNested(s, key, map_) {
	if (type(s[key]) == "object")
		return s[key];
	if (type(s[key]) == "string" && s[key] != "" && s[key] != "null") {
		let old = safeJson(s[key]);
		if (type(old) == "object")
			return old;
	}
	return fromFlat(s, map_);
}

function reviveServer(s) {
	let transport = reviveTransport(s);
	let reality = reviveNested(s, "reality", REALITY);
	let obfs = reviveNested(s, "obfs", OBFS);
	let alpn = reviveAlpn(s);
	for (let flat in TRANSPORT) delete s[flat];
	for (let flat in REALITY) delete s[flat];
	for (let flat in OBFS) delete s[flat];
	s.transport = transport;
	s.reality = reality;
	s.obfs = obfs;
	s.alpn = alpn;
	// Единственное допустимое значение для vless-аутбаунда; форма его не хранит, а null тут — конфиг,
	// который xray отвергает целиком.
	if (s.encryption == null || s.encryption == "")
		s.encryption = "none";
	if (s.port != null)
		s.port = int(s.port);
	return s;
}

// Плоский вид для записи: вложенные ключи и ключи прежней схемы уходят, иначе следующее чтение
// подхватило бы устаревший JSON вместо только что отредактированных полей.
function flattenServer(s) {
	let out = {};
	for (let k in s)
		if (k != "transport" && k != "reality" && k != "obfs" && k != "alpn" && substr(k, 0, 1) != ".")
			out[k] = s[k];
	toFlat(out, s.transport, TRANSPORT);
	toFlat(out, (type(s.reality) == "object") ? s.reality : null, REALITY);
	toFlat(out, (type(s.obfs) == "object") ? s.obfs : null, OBFS);
	out.alpn = (type(s.alpn) == "array") ? join(",", s.alpn) : "";
	return out;
}

export { reviveServer, flattenServer };
