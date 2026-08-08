// Нормализация hysteria2-URI в ТОТ ЖЕ server-контракт, что и vless (см. subscription.uc):
//   hysteria2://<auth>@<host>[:port]/?sni=&insecure=&obfs=&obfs-password=&pinSHA256=&mport=#tag
//
// Протокол — свойство сервера, а не отдельный список: порядок, дедуп, выбор активного и failover
// работают поверх общего контракта и о протоколе не знают. Поля vless (uuid/flow/reality и детали
// transport) остаются пустыми — у hysteria свой QUIC-транспорт, а не xray-овский stream.

import { urldecode } from "../lib/uri.uc";
import { truncate } from "../lib/text.uc";

const DEFAULT_PORT = 443;

function isOn(v) {
	return v == "1" || v == "true" || v == "yes";
}

function normalizeHysteria2(u, raw) {
	let port = (u.port != null) ? u.port : DEFAULT_PORT;
	if (port < 1 || port > 65535)
		return { error: "invalid port: " + truncate(raw), code: "invalid_port" };
	// Нечисловой «порт» (частый случай — диапазон порт-хоппинга прямо в адресе, `host:10000-20000`)
	// parseUri оставляет частью host. Молча подставить сюда 443 значит собрать конфиг с сервером
	// "host:10000-20000:443" — снаружи это «сервер не работает». У vless такой URI отвергается,
	// и здесь тоже: диапазон задаётся параметром mport.
	if (u.port == null && index(u.host, ":") >= 0 && !match(u.host, /:[0-9]+$/))
		return { error: "invalid port: " + truncate(raw), code: "invalid_port" };

	let q = u.query;
	let obfs = null;
	if (q.obfs != null && q.obfs != "")
		obfs = { type: q.obfs, password: q["obfs-password"] || "" };

	let server = {
		tag: (u.fragment != null && u.fragment != "") ? u.fragment : sprintf("%s:%d", u.host, port),
		protocol: "hysteria2",
		address: u.host,
		port: port,
		// Пароль аутентификации — это ВЕСЬ userinfo (панели пишут туда и `user:pass`), и он приходит
		// процентно-закодированным: parseUri декодирует только fragment.
		password: (u.user != null) ? urldecode(u.user) : "",
		uuid: "",
		encryption: "none",
		flow: "",
		security: "tls",
		sni: q.sni || q.peer || u.host,
		fingerprint: "",
		alpn: [],
		reality: null,
		transport: { type: "quic", path: "", host: "", mode: "", serviceName: "" },
		obfs: obfs,
		insecure: isOn(q.insecure) ? "1" : "0",
		pin_sha256: q.pinSHA256 || "",
		// Порт-хоппинг: у hysteria диапазон — часть адреса сервера ("host:10000-20000"), отдельного
		// поля нет. Держим строкой как пришло: проверить диапазон здесь нечем, битое значение
		// отвергнет сам клиент при старте, и это честнее молчаливой нормализации.
		mport: q.mport || "",
		source: "subscription",
	};
	return { server: server };
}

export { normalizeHysteria2 };
