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

export { LEGACY_SUB, isManual, serverSub };
