// rpcd ucode-плагин monkey-business (РАНТАЙМ, device-side).
// Регистрирует ubus-объект 'monkey-business' и делегирует логику чистым хендлерам.
//
// ВЕРИФИКАЦИЯ: только на устройстве/в dev-VM (нужны модули uci/fs + uclient-fetch +
// init.d + xray). Чистая логика покрыта host-тестами (test/unit/rpcd_test.uc).
//
// Установка (см. packaging): src/* -> /usr/share/rpcd/ucode/lib/monkey-business/*
'use strict';

import * as uci from 'uci';
import { popen, writefile, readfile, stat } from 'fs';
// АБСОЛЮТНЫЙ путь: rpcd-mod-ucode компилирует плагин из буфера (без пути к файлу),
// поэтому относительный import не резолвится. Транзитивные импорты в lib/ грузятся из
// файла и остаются относительными. Путь = место установки (см. шапку и deploy/packaging).
import * as h from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/handlers.uc';

const CONFIG = 'monkey-business';
const CONF_DIR = '/etc/monkey-business';
const XRAY_CONF = CONF_DIR + '/xray.json';
const GEO_DIR = '/usr/share/xray';
const GEO_SCRIPT = '/usr/share/monkey-business/update-geo.sh';

function shq(s) {
	return "'" + replace(s != null ? s : '', "'", "") + "'";
}

function runCapture(cmd) {
	let p = popen(cmd + '; echo "MB_EXIT:$?"');
	let out = p ? p.read('all') : '';
	if (p) p.close();
	return { out: (out != null) ? out : '', ok: index(out != null ? out : '', 'MB_EXIT:0') >= 0 };
}

function firstLine(s) {
	let parts = split(trim(s != null ? s : ''), "\n");
	return length(parts) > 0 ? trim(parts[0]) : '';
}

function loadSection(cursor, type_) {
	let res = {};
	cursor.foreach(CONFIG, type_, function(s) { res = s; });
	return res;
}

function loadServers(cursor) {
	let servers = [];
	cursor.foreach(CONFIG, 'server', function(s) { push(servers, s); });
	return servers;
}

function geoPresent() {
	return stat(GEO_DIR + '/geoip.dat') != null && stat(GEO_DIR + '/geosite.dat') != null;
}

// Скачивает тело подписки + захватывает заголовок Subscription-Userinfo (uclient-fetch -S).
function fetchSubscription(url) {
	let hdr = '/tmp/mb-sub.hdr';
	let p = popen('uclient-fetch -T 15 -S -O - ' + shq(url) + ' 2>' + hdr);
	if (p == null)
		return null;
	let body = p.read('all');
	p.close();
	if (body == null || length(body) == 0)
		return null;
	let userinfo = '';
	let raw = readfile(hdr);
	if (raw != null)
		for (let line in split(raw, "\n"))
			if (index(lc(line), 'subscription-userinfo:') >= 0)
				userinfo = trim(substr(line, index(line, ':') + 1));
	return { body: body, userinfo: userinfo };
}

function tcpPing(server) {
	let r = runCapture(sprintf('nc -z -w2 %s %d 2>/dev/null && echo ok', server.address, int(server.port)));
	return (index(r.out, 'ok') >= 0) ? 1 : null;
}

// Валидирует конфиг реальным xray, при успехе устанавливает + перезапускает сервис.
// Возврат: строка-ошибка | null(успех).
function applyConfig(jsonStr) {
	system('mkdir -p ' + CONF_DIR);
	if (!geoPresent())
		system('sh ' + GEO_SCRIPT + ' >/dev/null 2>&1');
	writefile('/tmp/mb-xray.json', jsonStr);
	let v = runCapture('xray run -test -c /tmp/mb-xray.json 2>/tmp/mb-xray.err');
	if (!v.ok) {
		let err = readfile('/tmp/mb-xray.err');
		let msg = firstLine(err != null ? err : v.out);
		return (msg != '') ? msg : 'xray config validation failed';
	}
	writefile(XRAY_CONF, jsonStr);
	system('/etc/init.d/monkey-business restart');
	return null;
}

function buildCtx() {
	let cursor = uci.cursor();
	return {
		getGlobal: function() { return loadSection(cursor, 'global'); },
		getDns: function() { return loadSection(cursor, 'dns'); },
		getAntiDpi: function() { return loadSection(cursor, 'anti_dpi'); },
		getSubscription: function() { return loadSection(cursor, 'subscription'); },
		getServers: function() { return loadServers(cursor); },
		setServers: function(servers) {
			cursor.foreach(CONFIG, 'server', function(s) { cursor.delete(CONFIG, s['.name']); });
			for (let s in servers) {
				let name = cursor.add(CONFIG, 'server');
				for (let k in s)
					cursor.set(CONFIG, name, k, s[k]);
			}
			cursor.commit(CONFIG);
		},
		getSelectedServer: function() {
			let sel = cursor.get(CONFIG, 'selected', 'server');
			let found = null;
			for (let s in loadServers(cursor))
				if (s.tag == sel)
					found = s;
			return found;
		},
		setSelected: function(tag) {
			cursor.set(CONFIG, 'selected', 'server', tag);
			cursor.commit(CONFIG);
		},
		setSubscriptionUrl: function(url) {
			cursor.set(CONFIG, 'subscription', 'url', url);
			cursor.commit(CONFIG);
		},
		setUserinfo: function(o) {
			cursor.set(CONFIG, 'subscription', 'used_upload', o.used_upload || '');
			cursor.set(CONFIG, 'subscription', 'used_download', o.used_download || '');
			cursor.set(CONFIG, 'subscription', 'total', o.total || '');
			cursor.set(CONFIG, 'subscription', 'expire', o.expire || '');
			cursor.commit(CONFIG);
		},
		fetchSubscription: function(url) { return fetchSubscription(url); },
		pingServer: function(s) { return tcpPing(s); },
		applyConfig: function(jsonStr) { return applyConfig(jsonStr); },
		stopService: function() { system('/etc/init.d/monkey-business stop'); },
		serviceRunning: function() {
			return index(runCapture('pgrep -x xray >/dev/null && echo up').out, 'up') >= 0;
		},
		setEnabled: function(on) {
			cursor.set(CONFIG, 'global', 'enabled', on ? '1' : '0');
			cursor.commit(CONFIG);
		},
		updateGeo: function() {
			let r = runCapture('sh ' + GEO_SCRIPT + ' 2>&1');
			return { status: r.ok ? 'ok' : 'error', present: geoPresent(), detail: firstLine(r.out) };
		},
	};
}

const methods = {
	status:               { call: function() { return h.status(buildCtx()); } },
	servers_list:         { call: function() { return h.serversList(buildCtx()); } },
	servers_ping:         { call: function() { return h.serversPing(buildCtx()); } },
	subscription_update:  { args: { url: '' }, call: function(req) { return h.subscriptionUpdate(buildCtx(), req.args); } },
	config_apply:         { call: function() { return h.configApply(buildCtx()); } },
	service_toggle:       { args: { enabled: false }, call: function(req) { return h.serviceToggle(buildCtx(), req.args); } },
	geo_update:           { call: function() { return h.geoUpdate(buildCtx()); } },
};

return { 'monkey-business': methods };
