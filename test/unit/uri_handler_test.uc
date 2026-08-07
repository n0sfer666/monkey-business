import { test, assertEq, run } from "../harness.uc";
import { parseServerUri } from "../../src/rpcd/uri.uc";

// Форма ссылки — один в один та, что выдаёт панель (порядок параметров, obfs, insecure), но креды и
// адрес выдуманные: настоящему паролю в репозитории делать нечего.
const HY2 = "hy2://Ex4mplePassw0rdF0rTests1@203.0.113.7:443/?sni=www.googletagmanager.com" +
	"&insecure=1&obfs=salamander&obfs-password=s4lam4nderTestObfsKey002#vdska-hy2";
// pbk — x25519-ключ: 43 символа base64url; sid — hex чётной длины. Обрезанные значения проверка
// отвергает, поэтому в фикстуре они настоящей формы.
const PBK = "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0";
const VLESS = "vless://11111111-2222-3333-4444-555555555555@ru.example:443" +
	"?security=reality&pbk=" + PBK + "&sid=a1b2c3d4&type=xhttp&path=/x&mode=auto&sni=www.example#ru-speed";

function ctx(servers) {
	return { getServers: function() { return servers || []; } };
}

function parse(uri, servers) {
	return parseServerUri(ctx(servers), { uri: uri });
}

test("hysteria2 link is accepted and flattened", function() {
	let r = parse(HY2);
	assertEq(r.ok, true);
	assertEq(r.protocol, "hysteria2");
	assertEq(r.server.tag, "vdska-hy2");
	assertEq(r.server.address, "203.0.113.7");
	assertEq(r.server.port, 443);
	assertEq(r.server.password, "Ex4mplePassw0rdF0rTests1");
	assertEq(r.server.sni, "www.googletagmanager.com");
	assertEq(r.server.obfs_type, "salamander");
	assertEq(r.server.obfs_password, "s4lam4nderTestObfsKey002");
	assertEq(r.server.source, "manual");
});

test("vless reality link is accepted", function() {
	let r = parse(VLESS);
	assertEq(r.ok, true);
	assertEq(r.protocol, "vless");
	assertEq(r.server.uuid, "11111111-2222-3333-4444-555555555555");
	assertEq(r.server.pbk, PBK);
	assertEq(r.server.sid, "a1b2c3d4");
	assertEq(r.server.tr_type, "xhttp");
	assertEq(r.server.tr_path, "/x");
	assertEq(r.warnings, []);
});

// insecure=1 отключает проверку сертификата — сервер поднимется, поэтому это предупреждение,
// а не отказ.
test("insecure is a warning, not a rejection", function() {
	assertEq(parse(HY2).warnings, ["insecure"]);
});

test("unsupported scheme is reported with the scheme itself", function() {
	let r = parse("vmess://eyJhZGQiOiJ4In0=");
	assertEq(r.ok, null);
	assertEq(r.error, "unsupported_scheme");
	assertEq(r.detail, "vmess");
});

test("garbage is unparseable", function() {
	assertEq(parse("not a link at all").error, "unparseable");
	assertEq(parse("   ").error, "empty");
});

// Форма заводит ОДИН сервер: пачку ссылок надо гнать через подписку, а не молча брать первую.
test("several links at once are rejected", function() {
	let r = parse(HY2 + "\n" + VLESS);
	assertEq(r.error, "multiple_links");
	assertEq(r.detail, "2");
});

test("vless without a uuid is rejected", function() {
	assertEq(parse("vless://@ru.example:443?security=tls").error, "missing_uuid");
});

// Формат UUID не проверяем: xray принимает любую строку до 30 байт и выводит из неё UUIDv5 —
// панели так и делают. Проверяем ровно ту границу, на которой он отказывается стартовать.
test("a non-uuid id is accepted up to 30 characters and rejected beyond", function() {
	assertEq(parse("vless://panel-user-42@h.example:443?security=tls").ok, true);
	let long = "0123456789012345678901234567890";
	assertEq(parse("vless://" + long + "@h.example:443?security=tls").error, "invalid_uuid");
});

// Копипаста с переносом внутри адреса даёт хост с пробелом. Разбор такую строку принимает, а
// сервер не поднимется — из формы это выглядит как «сохранил, и не работает».
test("a malformed address is rejected", function() {
	let r = parse("vless://u@h exa.mple:443?security=tls");
	assertEq(r.error, "invalid_host");
	assertEq(r.detail, "h exa.mple");
});

test("hysteria2 without a password is rejected", function() {
	assertEq(parse("hy2://1.2.3.4:443/?sni=s").error, "missing_password");
});

// Reality без публичного ключа стартует и молча не соединяется — снаружи неотличимо от
// «сервер лежит», поэтому ловим здесь.
test("reality without a public key is rejected", function() {
	assertEq(parse("vless://u@h.example:443?security=reality&sid=S").error, "missing_reality_key");
});

// Обрезанный при копировании ключ xray принимает при старте и молча не соединяется — то же самое
// «сервер лежит», что и без ключа вовсе.
test("a malformed reality key is rejected", function() {
	let r = parse("vless://u@h.example:443?security=reality&pbk=PBK");
	assertEq(r.error, "invalid_reality_key");
	assertEq(r.detail, "PBK");
});

test("a non-hex or odd-length short id is rejected", function() {
	assertEq(parse("vless://u@h.example:443?security=reality&pbk=" + PBK + "&sid=zz").error,
		"invalid_short_id");
	assertEq(parse("vless://u@h.example:443?security=reality&pbk=" + PBK + "&sid=abc").error,
		"invalid_short_id");
	assertEq(parse("vless://u@h.example:443?security=reality&pbk=" + PBK + "&sid=").ok, true);
});

// XTLS-vision работает только поверх голого TCP и только с TLS/Reality: в остальных сочетаниях
// xray отказывается поднимать аутбаунд.
test("flow xtls-rprx-vision outside plain TCP + TLS is rejected", function() {
	let base = "vless://u@h.example:443?flow=xtls-rprx-vision";
	assertEq(parse(base + "&security=tls&type=ws").error, "flow_needs_tcp");
	assertEq(parse(base + "&security=none").error, "flow_needs_tls");
	assertEq(parse(base + "&security=tls").ok, true);
	assertEq(parse(base + "-udp443&security=tls").ok, true);
});

// Незнакомый flow xray отвергает при старте, а форма его и показать не может — в списке ровно два
// значения, и el.setValue() мимо списка молча дал бы пустое поле.
test("an unknown flow is rejected", function() {
	let r = parse("vless://u@h.example:443?security=tls&flow=xtls-rprx-direct");
	assertEq(r.error, "unsupported_flow");
	assertEq(r.detail, "xtls-rprx-direct");
});

// Панель может прислать mlkem-шифрование: подставить вместо него "none" значит отдать xray конфиг,
// который не соединяется.
test("a non-default encryption reaches the flat layout", function() {
	let r = parse("vless://u@h.example:443?security=tls&encryption=mlkem768x25519plus.native.600s");
	assertEq(r.ok, true);
	assertEq(r.server.encryption, "mlkem768x25519plus.native.600s");
});

test("salamander without a password is rejected", function() {
	assertEq(parse("hy2://pw@h.example:443/?obfs=salamander").error, "missing_obfs_password");
});

test("a port outside 1-65535 is rejected", function() {
	assertEq(parse("vless://u@h.example:70000?security=tls").error, "invalid_port");
});

// Диапазон порт-хоппинга в адресе (host:10000-20000) — не порт: у hysteria он задаётся mport.
test("a port-hopping range in the address is rejected", function() {
	assertEq(parse("hy2://pw@h.example:10000-20000/").error, "invalid_port");
});

test("an unsupported transport is rejected", function() {
	assertEq(parse("vless://u@h.example:443?security=tls&type=kcp").error, "unsupported_transport");
});

test("an unsupported security is rejected", function() {
	assertEq(parse("vless://u@h.example:443?security=xtls").error, "unsupported_security");
});

test("an unsupported obfs is rejected", function() {
	assertEq(parse("hy2://pw@h.example:443/?obfs=whatever").error, "unsupported_obfs");
});

function sameAsHy2(name, tag) {
	return {
		'.name': name, tag: tag, protocol: "hysteria2", address: "203.0.113.7", port: 443,
		password: "Ex4mplePassw0rdF0rTests1", uuid: "", encryption: "none", flow: "",
		security: "tls", sni: "www.googletagmanager.com", fingerprint: "", alpn: [], reality: null,
		transport: { type: "quic", path: "", host: "", mode: "", serviceName: "" },
		obfs: { type: "salamander", password: "s4lam4nderTestObfsKey002" },
		insecure: "1", pin_sha256: "", mport: "", source: "subscription",
	};
}

// Переименованный дубль — всё равно дубль: сверяем параметры подключения, а не имя.
test("a link matching an existing server warns with its tag", function() {
	let r = parse(HY2, [sameAsHy2("cfg01", "already-here")]);
	assertEq(r.ok, true);
	assertEq(r.duplicate, "already-here");
	assertEq(r.warnings, ["insecure", "duplicate"]);
});

// Обновить креды существующего сервера вставкой свежей ссылки — штатный сценарий: сервер не должен
// оказаться дублем самого себя.
test("the section being edited is not its own duplicate", function() {
	let servers = [sameAsHy2("cfg01", "already-here")];
	assertEq(parseServerUri(ctx(servers), { uri: HY2, section: "cfg01" }).duplicate, null);
	assertEq(parseServerUri(ctx(servers), { uri: HY2, section: "cfg02" }).duplicate, "already-here");
});

test("a different server is not flagged as a duplicate", function() {
	let r = parse(HY2, [{ tag: "other", protocol: "vless", address: "9.9.9.9", port: 443 }]);
	assertEq(r.duplicate, null);
});

exit(run());
