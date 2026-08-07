import { test, assertEq, run } from "../harness.uc";
import { reviveServer, flattenServer } from "../../src/lib/servermap.uc";

function vlessServer() {
	return {
		tag: "ru", protocol: "vless", address: "x.example", port: 443, uuid: "u1",
		encryption: "none", flow: "", security: "reality", sni: "s.example", fingerprint: "chrome",
		alpn: ["h2", "http/1.1"],
		reality: { publicKey: "PBK", shortId: "SID", spiderX: "/" },
		transport: { type: "xhttp", path: "/p", host: "h.example", mode: "auto", serviceName: "" },
		obfs: null, source: "subscription",
	};
}

test("flatten spreads the nested objects into plain options", function() {
	let f = flattenServer(vlessServer());
	assertEq(f.tr_type, "xhttp");
	assertEq(f.tr_path, "/p");
	assertEq(f.tr_host, "h.example");
	assertEq(f.tr_mode, "auto");
	assertEq(f.pbk, "PBK");
	assertEq(f.sid, "SID");
	assertEq(f.spx, "/");
	assertEq(f.alpn, "h2,http/1.1");
	assertEq(f.transport, null);
	assertEq(f.reality, null);
});

// Сравнение поштучно, а не всего объекта: харнесс сверяет JSON-строки, а revive переставляет
// вложенные ключи в конец — порядок полей ничего не значит ни для генератора, ни для UCI.
function assertSameServer(actual, expected) {
	for (let k in expected)
		assertEq(actual[k], expected[k], "field " + k);
}

test("revive rebuilds the contract from the plain options", function() {
	assertSameServer(reviveServer(flattenServer(vlessServer())), vlessServer());
});

test("hysteria2 obfs survives the round trip", function() {
	let s = {
		tag: "hy", protocol: "hysteria2", address: "1.2.3.4", port: 443, password: "pw",
		uuid: "", encryption: "none", flow: "", security: "tls", sni: "s", fingerprint: "",
		alpn: [], reality: null,
		transport: { type: "quic", path: "", host: "", mode: "", serviceName: "" },
		obfs: { type: "salamander", password: "op" },
		insecure: "1", pin_sha256: "", mport: "", source: "manual",
	};
	let f = flattenServer(s);
	assertEq(f.obfs_type, "salamander");
	assertEq(f.obfs_password, "op");
	assertSameServer(reviveServer(f), s);
});

// Порт из UCI приходит строкой, а генератор кладёт его в конфиг как число.
test("revive turns the port back into a number", function() {
	let s = reviveServer({ tag: "t", protocol: "vless", address: "a", port: "8443" });
	assertEq(s.port, 8443);
});

// На устройстве уже лежат серверы, записанные прежней схемой: до первого обновления подписки они
// обязаны читаться как раньше, иначе апгрейд пакета молча ломает рабочий туннель.
test("revive still understands the old JSON-string layout", function() {
	let s = reviveServer({
		tag: "old", protocol: "vless", address: "a", port: "443",
		transport: '{"type":"ws","path":"/w","host":"hh","mode":"","serviceName":""}',
		reality: '{"publicKey":"P","shortId":"S","spiderX":"/"}',
		alpn: '["h2"]',
		obfs: "null",
	});
	assertEq(s.transport.type, "ws");
	assertEq(s.transport.path, "/w");
	assertEq(s.reality.publicKey, "P");
	assertEq(s.alpn, ["h2"]);
	assertEq(s.obfs, null);
});

// Пустая секция (сервер заведён в форме и ещё не заполнен) не должна давать ни null-транспорта,
// ни выдуманного reality: генератор читает transport.type без проверок.
test("revive defaults an empty section to tcp with no reality", function() {
	let s = reviveServer({ tag: "new", protocol: "vless", address: "a", port: "443" });
	assertEq(s.transport, { type: "tcp", path: "", host: "", mode: "", serviceName: "" });
	assertEq(s.reality, null);
	assertEq(s.obfs, null);
	assertEq(s.alpn, []);
});

// Форма не хранит encryption отдельной опцией: у vless допустимо единственное значение, а null в
// этом поле xray отвергает вместе со всем конфигом.
test("revive fills in the vless encryption", function() {
	assertEq(reviveServer({ tag: "t", protocol: "vless", address: "a", port: "443" }).encryption, "none");
	assertEq(reviveServer({ tag: "t", encryption: "mlkem768x25519plus" }).encryption, "mlkem768x25519plus");
});

// /etc/config правят руками: битый блоб прежней схемы не должен ронять чтение списка, а с ним и
// все ubus-методы разом.
test("revive survives a broken JSON blob", function() {
	let s = reviveServer({
		tag: "t", address: "a", port: "443",
		transport: '{"type":', reality: "{oops", alpn: '["h2"',
	});
	assertEq(s.transport.type, "tcp");
	assertEq(s.reality, null);
	assertEq(s.alpn, []);
});

// Служебные ключи UCI (.name/.type/.index) не должны улетать обратно в конфиг отдельными опциями.
test("flatten drops the UCI bookkeeping keys", function() {
	let f = flattenServer({
		'.name': 'cfg01', '.type': 'server', '.index': 3, '.anonymous': true,
		tag: "t", address: "a", port: 443, alpn: [], transport: null, reality: null, obfs: null,
	});
	assertEq(f['.name'], null);
	assertEq(f['.type'], null);
	assertEq(f['.index'], null);
	assertEq(f.tag, "t");
});

// Форма правит плоские опции; если бы прежний JSON остался в секции, следующее чтение вернуло бы
// старый транспорт и правка исчезла бы без следа.
test("flatten clears a stale JSON layout left by the old schema", function() {
	let s = reviveServer({
		tag: "t", address: "a", port: "443",
		transport: '{"type":"ws","path":"/old","host":"","mode":"","serviceName":""}',
	});
	s.transport.path = "/new";
	let f = flattenServer(s);
	assertEq(f.transport, null);
	assertEq(f.tr_path, "/new");
});

exit(run());
