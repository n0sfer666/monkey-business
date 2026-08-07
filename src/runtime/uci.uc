// Чтение/запись UCI-секций плагина. Раскладку server-контракта по опциям держит lib/servermap.uc.

import { readfile, writefile } from 'fs';
import { CONFIG, CONF_DIR, ACTIVE_FILE } from './paths.uc';
import { reviveServer, flattenServer } from '../lib/servermap.uc';

function loadSection(cursor, type_) {
	let res = {};
	cursor.foreach(CONFIG, type_, function(s) { res = s; });
	return res;
}

function loadServers(cursor) {
	let servers = [];
	cursor.foreach(CONFIG, 'server', function(s) { push(servers, reviveServer(s)); });
	return servers;
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

function selectedServer(cursor) {
	let sel = readfile(ACTIVE_FILE);
	sel = (sel != null) ? trim(sel) : '';
	let found = null;
	for (let s in loadServers(cursor))
		if (s.tag == sel)
			found = s;
	return found;
}

// Атомарно и с проверкой: на ro-remounted корне (ровно то состояние, против которого весь этот
// модуль) молчаливый провал записи оставил бы UI с «Server: none» без единого следа.
function storeSelected(sh, tag) {
	let cur = readfile(ACTIVE_FILE);
	let want = tag + '\n';
	if (cur == want)
		return;
	system('mkdir -p ' + CONF_DIR);
	let tmp = CONF_DIR + '/.active.new';
	if (writefile(tmp, want) != length(want) || !sh.runCapture('mv ' + tmp + ' ' + ACTIVE_FILE).ok) {
		system('rm -f ' + tmp);
		system('logger -t mb-event ' + sh.shq('rpcd: cannot record active server (rootfs read-only?)'));
	}
}

export { loadSection, loadServers, storeServers, selectedServer, storeSelected };
