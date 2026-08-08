// Разбор одной ссылки для формы «добавить сервер»: тот же путь, которым идёт подписка, плюс
// строгая проверка (parser/validate.uc) и предупреждения. Форма не имеет своего парсера намеренно —
// иначе она принимала бы ссылки, которые устройство поднять не может.

import { parseUri } from "../lib/uri.uc";
import { normalizeUri } from "../parser/subscription.uc";
import { validateServer } from "../parser/validate.uc";
import { flattenServer } from "../lib/servermap.uc";
import { connectionKey } from "./subscription.uc";

function nonEmptyLines(text) {
	let out = [];
	for (let line in split(text, "\n"))
		if (trim(line) != "")
			push(out, trim(line));
	return out;
}

// exclude — секция, которую правят прямо сейчас: вставить в существующий сервер его же ссылку
// (штатный способ обновить креды) не должно выглядеть как «этот сервер уже есть».
function duplicateTag(ctx, s, exclude) {
	let key = connectionKey(s);
	for (let old in ctx.getServers()) {
		if (exclude != "" && old[".name"] == exclude)
			continue;
		if (connectionKey(old) == key)
			// Безымянный дубль всё равно надо чем-то назвать: пустая строка в предупреждении выглядит
			// как «уже есть как ""».
			return (old.tag != null && old.tag != "") ? old.tag : sprintf("%s:%s", old.address, old.port);
	}
	return null;
}

function parseServerUri(ctx, args) {
	let raw = (args != null && args.uri != null) ? trim(args.uri) : "";
	if (raw == "")
		return { error: "empty" };
	// Вставили пачку ссылок — это подписка, а не сервер. Молча взять первую значило бы потерять
	// остальные без единого следа.
	let lines = nonEmptyLines(raw);
	if (length(lines) > 1)
		return { error: "multiple_links", detail: "" + length(lines) };

	let u = parseUri(lines[0]);
	if (u == null)
		return { error: "unparseable" };

	let r = normalizeUri(u, lines[0]);
	if (r.error != null)
		return { error: r.code || "unparseable", detail: r.detail || "" };

	let v = validateServer(r.server);
	if (v.error != null)
		return { error: v.error, detail: v.detail };

	let server = r.server;
	server.source = "manual";
	let exclude = (args != null && args.section != null) ? "" + args.section : "";
	let dup = duplicateTag(ctx, server, exclude);
	let warnings = v.warnings;
	if (dup != null)
		push(warnings, "duplicate");
	// Плоский вид — ровно то, что форма кладёт в опции UCI: раскладку знает servermap, а не JS.
	return {
		ok: true, protocol: server.protocol, server: flattenServer(server),
		warnings: warnings, duplicate: dup,
	};
}

export { parseServerUri };
