// Подписка: разбор ответа панели и сохранение списка серверов с УЧЁТОМ ручного порядка.

import { parse } from "../parser/subscription.uc";
import { selectBest } from "./select.uc";

// "upload=0; download=123; total=456; expire=789" -> объект (значения строками)
function parseUserinfo(s) {
	let out = { used_upload: "", used_download: "", total: "", expire: "" };
	if (type(s) != "string" || trim(s) == "")
		return out;
	for (let part in split(s, ";")) {
		let kv = split(trim(part), "=");
		if (length(kv) != 2)
			continue;
		let k = trim(kv[0]), v = trim(kv[1]);
		if (k == "upload") out.used_upload = v;
		else if (k == "download") out.used_download = v;
		else if (k == "total") out.total = v;
		else if (k == "expire") out.expire = v;
	}
	return out;
}

// Всё, чем задаётся ПОДКЛЮЧЕНИЕ, без имени: по этому же признаку форма узнаёт, что вставленная
// ссылка ведёт на уже заведённый сервер (переименованный дубль — всё равно дубль).
//
// Поля берутся ПО ПРОТОКОЛУ: у hysteria2 учётные данные лежат в password/obfs (без них два разных
// сервера на одном адресе схлопнулись бы в один), а vless-поля (uuid, security, transport, reality)
// к его подключению отношения не имеют — форма их у hysteria2-сервера и не хранит, так что общий
// набор ключей делал бы один и тот же сервер «разным» в зависимости от способа заведения.
function connectionKey(s) {
	let base = [ s.protocol || "vless", s.address || "", "" + (s.port || ""), s.sni || "" ];
	if ((s.protocol || "vless") == "hysteria2") {
		let ob = (type(s.obfs) == "object") ? s.obfs : {};
		push(base, s.password || "", ob.type || "", ob.password || "",
			(s.insecure == "1") ? "1" : "0", s.pin_sha256 || "", s.mport || "");
		return join("|", base);
	}
	let tr = (type(s.transport) == "object") ? s.transport : {};
	let re = (type(s.reality) == "object") ? s.reality : {};
	push(base, s.uuid || "", s.security || "", s.flow || "", s.fingerprint || "",
		(type(s.alpn) == "array") ? join(",", s.alpn) : "",
		re.publicKey || "", re.shortId || "", re.spiderX || "",
		tr.type || "", tr.path || "", tr.host || "", tr.mode || "", tr.serviceName || "");
	return join("|", base);
}

function serverKey(s) {
	return (s.tag || "") + "|" + connectionKey(s);
}

// Заведён руками (форма LuCI), а не подпиской. Секция, созданная в форме, может вообще не иметь
// source — подписка же проставляет его всегда, поэтому «не subscription» и есть признак ручного.
function isManual(s) {
	return s.source != "subscription";
}

// СОХРАНИТЬ РУЧНОЙ ПОРЯДОК: выдать существующие серверы в их текущем порядке (матч по ключу,
// данные обновляются из свежей подписки), новые — в конец. Иначе re-fetch (Save&Apply/
// автообновление) сбрасывал бы drag-сортировку к порядку подписки.
//
// Ручные серверы переживают обновление на своей позиции: их нет в ответе панели, и без этого
// автообновление раз в сутки молча стирало бы всё, что добавлено ссылкой или руками. Совпавший по
// ключу сервер подписки при этом не добавляется вторым — данные у них одинаковы по определению
// ключа, а приоритет задаёт ручная позиция.
function mergeKeepingOrder(existing, fresh) {
	let byKey = {};
	for (let sv in fresh)
		byKey[serverKey(sv)] = sv;
	let ordered = [];
	let used = {};
	let manual = {};
	for (let old in existing) {
		let k = serverKey(old);
		if (isManual(old)) {
			push(ordered, old);
			used[k] = true;
			// Дубль ручного сервера ищем по подключению, а не по ключу с именем: сервер, добавленный
			// ссылкой и переименованный, иначе лёг бы в список вторым — уже из подписки.
			manual[connectionKey(old)] = true;
			continue;
		}
		if (byKey[k] != null && used[k] == null) {
			push(ordered, byKey[k]);
			used[k] = true;
		}
	}
	for (let sv in fresh) {
		let k = serverKey(sv);
		if (used[k] == null && manual[connectionKey(sv)] == null) {
			push(ordered, sv);
			used[k] = true;
		}
	}
	return ordered;
}

function subscriptionUpdate(ctx, args) {
	let url = (args != null && args.url != null && args.url != "") ? args.url : ctx.getSubscription().url;
	if (url == null || url == "")
		return { error: "no subscription url" };

	let resp = ctx.fetchSubscription(url);
	if (resp == null || resp.body == null)
		return { error: "fetch failed", kept: length(ctx.getServers()) };

	let res = parse(resp.body);
	if (length(res.servers) == 0)
		return { error: "no servers parsed", format: res.format, kept: length(ctx.getServers()) };

	ctx.setServers(mergeKeepingOrder(ctx.getServers(), res.servers));
	ctx.setSubscriptionUrl(url);
	if (resp.userinfo != null && resp.userinfo != "")
		ctx.setUserinfo(parseUserinfo(resp.userinfo));
	// Перевыбираем активный ТОЛЬКО если прежнего в списке больше нет. Обновление подписки идёт и по
	// крону (subupdate.sh, config_apply он намеренно не зовёт), а безусловный selectBest возвращал бы
	// указатель на servers[0] раз в сутки: failover, уведший трафик на живой сервер, оказывался бы
	// отменён на бумаге — дашборд показывал бы не тот сервер, через который идёт трафик, а watchdog
	// принял бы смену тега за ручной выбор человека, сбросил фазу и обнулил backoff посреди инцидента.
	if (ctx.getSelectedServer() == null)
		selectBest(ctx);
	return { format: res.format, added: length(res.servers), errors: res.errors };
}

export { subscriptionUpdate, parseUserinfo, serverKey, connectionKey };
