// Чтение/запись UCI-секций плагина. Раскладку server-контракта по опциям держит lib/servermap.uc.

import { readfile, writefile } from 'fs';
import { CONFIG, CONF_DIR, ACTIVE_FILE } from './paths.uc';
import { reviveServer, flattenServer } from '../lib/servermap.uc';
import { dropOrphans, subsOrLegacy, findSelected } from '../lib/subs.uc';

function loadSection(cursor, type_) {
	let res = {};
	cursor.foreach(CONFIG, type_, function(s) { res = s; });
	return res;
}

function loadSubscriptions(cursor) {
	let subs = [];
	cursor.foreach(CONFIG, 'subscription', function(s) { push(subs, s); });
	return subsOrLegacy(subs);
}

function loadServers(cursor) {
	let servers = [];
	cursor.foreach(CONFIG, 'server', function(s) { push(servers, reviveServer(s)); });
	return dropOrphans(servers, loadSubscriptions(cursor));
}

function storeServers(cursor, servers) {
	cursor.foreach(CONFIG, 'server', function(s) { cursor.delete(CONFIG, s['.name']); });
	for (let s in servers) {
		let name = cursor.add(CONFIG, 'server');
		let flat = flattenServer(s);
		for (let k in flat)
			if (flat[k] != null)
				cursor.set(CONFIG, name, k, "" + flat[k]);
	}
	cursor.commit(CONFIG);
}

function selectedId() {
	let sel = readfile(ACTIVE_FILE);
	return (sel != null) ? trim(sel) : '';
}

function selectedServer(cursor) {
	return findSelected(loadServers(cursor), selectedId());
}

// Атомарно и с проверкой: на ro-remounted корне (ровно то состояние, против которого весь этот
// модуль) молчаливый провал записи оставил бы UI с «Server: none» без единого следа.
function storeSelected(sh, id) {
	let cur = readfile(ACTIVE_FILE);
	let want = id + '\n';
	if (cur == want)
		return;
	system('mkdir -p ' + CONF_DIR);
	let tmp = CONF_DIR + '/.active.new';
	if (writefile(tmp, want) != length(want) || !sh.runCapture('mv ' + tmp + ' ' + ACTIVE_FILE).ok) {
		system('rm -f ' + tmp);
		system('logger -t mb-event ' + sh.shq('rpcd: cannot record active server (rootfs read-only?)'));
	}
}

export { loadSection, loadSubscriptions, loadServers, storeServers, selectedId, selectedServer, storeSelected };
