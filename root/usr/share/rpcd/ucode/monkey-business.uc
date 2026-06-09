// rpcd ucode-плагин monkey-business (РАНТАЙМ, device-side).
// Регистрирует ubus-объект 'monkey-business' и делегирует логику чистым хендлерам.
//
// ВЕРИФИКАЦИЯ: только на устройстве/в dev-VM (нужны модули uci/fs + uclient-fetch +
// init.d). Чистая логика покрыта host-тестами (test/unit/rpcd_test.uc).
//
// Установка (см. packaging): src/* -> /usr/share/rpcd/ucode/lib/monkey-business/*
'use strict';

import * as uci from 'uci';
import { popen, writefile } from 'fs';
// АБСОЛЮТНЫЙ путь: rpcd-mod-ucode компилирует плагин из буфера (без пути к файлу),
// поэтому относительный import не резолвится. Транзитивные импорты в lib/ грузятся из
// файла и остаются относительными. Путь = место установки (см. шапку и deploy/packaging).
import * as h from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/handlers.uc';

const CONFIG = 'monkey-business';
const XRAY_CONF = '/etc/monkey-business/xray.json';

function loadGlobal(cursor) {
	let g = {};
	cursor.foreach(CONFIG, 'global', function(s) { g = s; });
	return g;
}

function loadServers(cursor) {
	let servers = [];
	cursor.foreach(CONFIG, 'server', function(s) { push(servers, s); });
	return servers;
}

function httpGet(url) {
	let p = popen('uclient-fetch -q -T 15 -O - ' + url + ' 2>/dev/null');
	if (p == null)
		return null;
	let body = p.read('all');
	p.close();
	return (body != null && length(body) > 0) ? body : null;
}

function tcpPing(server) {
	let p = popen(sprintf('nc -z -w2 %s %d 2>/dev/null && echo ok', server.address, server.port));
	if (p == null)
		return null;
	let res = p.read('all');
	p.close();
	return (index(res, 'ok') >= 0) ? 1 : null;
}

function buildCtx() {
	let cursor = uci.cursor();
	return {
		getGlobal: function() { return loadGlobal(cursor); },
		getSubscription: function() {
			let sub = {};
			cursor.foreach(CONFIG, 'subscription', function(s) { sub = s; });
			return sub;
		},
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
		fetchSubscription: function(url) { return httpGet(url); },
		pingServer: function(s) { return tcpPing(s); },
		applyConfig: function(jsonStr) {
			writefile(XRAY_CONF, jsonStr);
			system('/etc/init.d/monkey-business restart');
		},
		serviceRunning: function() {
			let p = popen('pgrep -x xray >/dev/null && echo up');
			let r = p ? p.read('all') : '';
			if (p) p.close();
			return index(r, 'up') >= 0;
		},
		setEnabled: function(on) {
			cursor.set(CONFIG, 'global', 'enabled', on ? '1' : '0');
			cursor.commit(CONFIG);
		},
		updateGeo: function() {
			system('/usr/share/monkey-business/update-geo.sh');
			return { status: 'started' };
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
