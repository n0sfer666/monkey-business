// Строгая проверка ОДНОЙ ссылки, вставленной в форму. Критерий один: «не поднимется — не валидно».
// Парсер подписки намеренно мягче (панель может прислать поле, которого мы не знаем, и терять из-за
// него весь сервер нельзя), поэтому проверки живут отдельным слоем и применяются только к ручному
// вводу — там человек видит ошибку сразу и может её исправить, а не ловит «сервер не работает».
//
// Коды, а не текст: сообщение рисует LuCI (см. luci/.../serverlink.js), тут только причина.

const TRANSPORTS = { tcp: true, ws: true, xhttp: true, grpc: true, httpupgrade: true };
const SECURITIES = { reality: true, tls: true, none: true };
const OBFS_TYPES = { salamander: true };
const FLOWS = { "xtls-rprx-vision": true, "xtls-rprx-vision-udp443": true };

// Скобки IPv6 снимает parseUri, так что в адресе их уже нет: остаются буквы, цифры, точки, дефисы
// и двоеточия IPv6 (плюс %zone). Пробел или слеш здесь — обрезанная копипаста, а не адрес.
function hostLooksSane(h) {
	return type(h) == "string" && h != "" && match(h, /^[A-Za-z0-9._:%-]+$/) != null;
}

function str(v) {
	return (v != null) ? "" + v : "";
}

function fail(code, detail) {
	return { error: code, detail: detail || "", warnings: [] };
}

// x25519-ключ Reality — 32 байта в base64url без padding, это ровно 43 символа. Обрезанный на
// копировании ключ xray принимает при старте и молча не соединяется.
function checkReality(re) {
	if (re == null || re.publicKey == null || re.publicKey == "")
		return fail("missing_reality_key");
	if (match(re.publicKey, /^[A-Za-z0-9_-]{43}=?$/) == null)
		return fail("invalid_reality_key", re.publicKey);
	// shortId — hex-строка до 8 байт; нечётная длина или не-hex ломает рукопожатие так же тихо.
	let sid = str(re.shortId);
	if (sid != "" && (match(sid, /^[0-9a-fA-F]+$/) == null || length(sid) > 16 || length(sid) % 2 != 0))
		return fail("invalid_short_id", sid);
	return null;
}

// XTLS-vision живёт только поверх TLS/Reality и только на голом TCP: с ws/grpc/xhttp и с
// security=none xray отказывается поднимать аутбаунд. Неизвестный flow он отвергает при старте, а
// форма всё равно не смогла бы его показать — в списке значений ровно эти два.
function checkFlow(s, transport) {
	let flow = str(s.flow);
	if (flow == "")
		return null;
	if (!FLOWS[flow])
		return fail("unsupported_flow", flow);
	if (s.security == "none")
		return fail("flow_needs_tls");
	if (transport != "tcp")
		return fail("flow_needs_tcp", transport);
	return null;
}

// Проверять формат UUID нельзя: xray принимает в id любую строку и, если это не UUID, выводит из
// неё UUIDv5 — панели этим пользуются. Ограничение у такой строки одно, зато жёсткое: длиннее 30
// байт xray отвергает вместе со всем конфигом.
function checkUuid(id) {
	if (match(id, /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/) != null)
		return null;
	return (length(id) > 30) ? fail("invalid_uuid", id) : null;
}

function checkVless(s) {
	if (s.uuid == null || s.uuid == "")
		return fail("missing_uuid");
	let badId = checkUuid(str(s.uuid));
	if (badId != null)
		return badId;
	if (!SECURITIES[s.security])
		return fail("unsupported_security", s.security);
	if (s.security == "reality") {
		let bad = checkReality(s.reality);
		if (bad != null)
			return bad;
	}
	let t = (s.transport != null) ? str(s.transport.type) : "";
	if (!TRANSPORTS[t])
		return fail("unsupported_transport", t);
	return checkFlow(s, t);
}

function checkHysteria2(s) {
	if (s.password == null || s.password == "")
		return fail("missing_password");
	if (s.obfs == null)
		return null;
	if (!OBFS_TYPES[s.obfs.type])
		return fail("unsupported_obfs", str(s.obfs.type));
	// Пустой пароль обфускации hysteria-клиент не принимает: обфускация включена, ключа нет.
	if (s.obfs.password == null || s.obfs.password == "")
		return fail("missing_obfs_password");
	return null;
}

// Всегда { error, detail, warnings }: error == null — ссылка валидна, warnings при этом могут быть.
function validateServer(s) {
	if (!hostLooksSane(s.address))
		return fail("invalid_host", s.address);
	if (s.port == null || s.port < 1 || s.port > 65535)
		return fail("invalid_port", "" + (s.port || ""));

	let bad = (s.protocol == "hysteria2") ? checkHysteria2(s) : checkVless(s);
	if (bad != null)
		return bad;

	let warnings = [];
	if (s.insecure == "1")
		push(warnings, "insecure");
	return { error: null, detail: "", warnings: warnings };
}

export { validateServer };
