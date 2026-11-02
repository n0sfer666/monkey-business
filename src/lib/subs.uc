const LEGACY_SUB = "subscription";

// Заведён руками (форма LuCI), а не подпиской. Секция, созданная в форме, может вообще не иметь
// source — подписка же проставляет его всегда, поэтому «не subscription» и есть признак ручного.
function isManual(s) {
	return s.source != "subscription";
}

function serverSub(s) {
	if (isManual(s))
		return null;
	return (s.sub != null && s.sub != "") ? s.sub : LEGACY_SUB;
}

function serverId(s) {
	let sub = serverSub(s);
	return (sub != null) ? sub + "/" + s.tag : s.tag;
}

function subId(sub) {
	return sub[".name"];
}

function findSub(subs, id) {
	for (let sub in subs)
		if (subId(sub) == id)
			return sub;
	return null;
}

function activeSubId(subs, want) {
	if (want != null && want != "" && findSub(subs, want) != null)
		return want;
	return (length(subs) > 0) ? subId(subs[0]) : null;
}

function num(v) {
	let n = int(v);
	return (type(n) == "int" && n > 0) ? n : 0;
}

function subDeath(sub, now) {
	let total = num(sub.total);
	if (total > 0 && num(sub.used_upload) + num(sub.used_download) >= total)
		return "exhausted";
	let expire = num(sub.expire);
	return (expire > 0 && now >= expire) ? "expired" : null;
}

function subAlive(sub, now) {
	return subDeath(sub, now) == null;
}

function nextAlive(subs, from, now) {
	let n = length(subs);
	let at = 0;
	for (let i = 0; i < n; i++)
		if (subId(subs[i]) == from)
			at = i;
	for (let k = 1; k < n; k++) {
		let sub = subs[(at + k) % n];
		if (subAlive(sub, now))
			return sub;
	}
	return null;
}

function selectError(subs, id, now) {
	let sub = (id != null && id != "") ? findSub(subs, id) : null;
	if (sub == null)
		return "unknown subscription";
	let dead = subDeath(sub, now);
	if (dead != null && nextAlive(subs, id, now) != null)
		return "subscription is " + dead + ": update it or pick an alive one";
	return null;
}

function dropOrphans(servers, subs) {
	return filter(servers, function(s) {
		let sub = serverSub(s);
		return sub == null || findSub(subs, sub) != null;
	});
}

function subsOrLegacy(subs) {
	return (length(subs) > 0) ? subs : [ { ".name": LEGACY_SUB } ];
}

function findSelected(servers, sel) {
	if (sel == null || sel == "")
		return null;
	for (let s in servers)
		if (serverId(s) == sel)
			return s;
	for (let s in servers)
		if (s.tag == sel)
			return s;
	return null;
}

export { LEGACY_SUB, isManual, serverSub, serverId, subId, findSub, activeSubId, subDeath, subAlive,
	nextAlive, selectError, dropOrphans, subsOrLegacy, findSelected };
