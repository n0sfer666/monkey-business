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
const GEO_SCRIPT = '/usr/share/monkey-business/geo.sh';

// POSIX single-quote экранирование: ' -> '\'' (закрыть кавычку, экранированный ', снова открыть).
// Раньше кавычки УДАЛЯЛИСЬ -> молчаливая порча URL/значений с апострофом.
function shq(s) {
	return "'" + replace(s != null ? s : '', "'", "'\\''") + "'";
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

// UCI хранит только строки/списки, а server имеет вложенные transport/reality (объекты) и alpn.
// Сериализуем их в JSON при записи (storeServer) и восстанавливаем при чтении (reviveServer).
function reviveServer(s) {
	for (let key in ["transport", "reality", "alpn"]) {
		if (type(s[key]) == "string") {
			let v = s[key];
			if (v == "" || v == "null")
				s[key] = (key == "alpn") ? [] : null;
			else
				s[key] = json(v);
		}
	}
	if (s.port != null)
		s.port = int(s.port);
	return s;
}

function loadServers(cursor) {
	let servers = [];
	cursor.foreach(CONFIG, 'server', function(s) { push(servers, reviveServer(s)); });
	return servers;
}

function geoPresent() {
	return stat(GEO_DIR + '/geoip.dat') != null && stat(GEO_DIR + '/geosite.dat') != null;
}

function haveCurl() {
	return stat('/usr/bin/curl') != null || stat('/bin/curl') != null;
}

// Тело подписки + (если есть curl) заголовок Subscription-Userinfo для трафика.
// uclient-fetch не умеет сохранять заголовки ответа -> userinfo доступен только с curl.
function fetchSubscription(url) {
	let bodyf = '/tmp/mb-sub.body', hdrf = '/tmp/mb-sub.hdr';
	system('rm -f ' + bodyf + ' ' + hdrf);
	// тело/заголовки содержат токен/UUID серверов -> umask 077: файлы создаются 0600 сразу,
	// без окна world-readable во время скачивания; подчистка после чтения ниже.
	if (haveCurl())
		runCapture('umask 077; curl -fsSL -m 25 -D ' + hdrf + ' -o ' + bodyf + ' ' + shq(url));
	else
		runCapture('umask 077; uclient-fetch -q -T 20 -O ' + bodyf + ' ' + shq(url));
	let body = readfile(bodyf);
	if (body == null || length(body) == 0) {
		system('rm -f ' + bodyf + ' ' + hdrf);
		return null;
	}
	let userinfo = '';
	let raw = readfile(hdrf);
	if (raw != null)
		for (let line in split(raw, "\n"))
			if (index(lc(line), 'subscription-userinfo:') >= 0)
				userinfo = trim(substr(line, index(line, ':') + 1));
	system('rm -f ' + bodyf + ' ' + hdrf);
	return { body: body, userinfo: userinfo };
}

function tcpPing(server) {
	// server.address — внешний вход из подписки -> shq (иначе shell-инъекция в popen)
	let r = runCapture(sprintf('nc -z -w2 %s %d 2>/dev/null && echo ok', shq(server.address), int(server.port)));
	return (index(r.out, 'ok') >= 0) ? 1 : null;
}

// Валидирует конфиг реальным xray, при успехе устанавливает + перезапускает сервис.
// Возврат: строка-ошибка | null(успех).
function applyConfig(jsonStr) {
	system('mkdir -p ' + CONF_DIR);
	if (!geoPresent())
		return 'geo databases missing — press "Update geo databases" on the Dashboard first';
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
				for (let k in s) {
					let v = s[k], t = type(v);
					if (t == "object" || t == "array")
						cursor.set(CONFIG, name, k, sprintf("%J", v));
					else if (v != null)
						cursor.set(CONFIG, name, k, "" + v);
				}
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
			// pidof надёжен на BusyBox (pgrep -x не матчит comm в этой сборке)
			return index(runCapture('pidof xray >/dev/null && echo up').out, 'up') >= 0;
		},
		setEnabled: function(on) {
			cursor.set(CONFIG, 'global', 'enabled', on ? '1' : '0');
			cursor.commit(CONFIG);
		},
		checkExit: function(domain) {
			let d = (domain != null && domain != '') ? domain : 'ip-api.com';
			if (match(d, /^[a-zA-Z0-9.\-]+$/) == null)
				return { error: 'bad domain' };
			// -x socks5h://: домен резолвит Xray -> срабатывают доменные правила сплита
			// (этот curl не знает длинный --socks5h, форма -x работает)
			let r = runCapture("curl -s -x socks5h://127.0.0.1:10808 --max-time 12 'http://" + d +
				"/json?fields=status,message,query,country,countryCode' 2>/dev/null");
			// curl не даёт trailing-\n -> маркер MB_EXIT клеится к JSON; отрезаем его
			let body = r.out;
			let cut = index(body, 'MB_EXIT:');
			if (cut >= 0)
				body = substr(body, 0, cut);
			body = trim(body);
			if (substr(body, 0, 1) != '{')
				return { error: 'нет ответа через proxy — VPN включён? сервис запущен?' };
			let j = json(body);
			if (type(j) != 'object')
				return { error: 'bad response' };
			if (j.status != null && j.status != 'success')
				return { error: j.message || 'lookup failed' };
			return { probe: d, ip: j.query || j.ip || '', country: j.country || '', code: j.countryCode || '' };
		},
		setCustomRouting: function(direct, proxy) {
			cursor.set(CONFIG, 'global', 'custom_direct', direct);
			cursor.set(CONFIG, 'global', 'custom_proxy', proxy);
			cursor.commit(CONFIG);
		},
		updateGeo: function(args) {
			// сохранить кастомные URL (commit на сервере, без LuCI-стейджинга)
			if (args != null && (args.geoip_url != null || args.geosite_url != null)) {
				cursor.set(CONFIG, 'geo', 'geoip_url', args.geoip_url || '');
				cursor.set(CONFIG, 'geo', 'geosite_url', args.geosite_url || '');
				cursor.commit(CONFIG);
			}
			// фон: скачивание ~29MB дольше ubus-таймаута (30s). UI поллит geo_status.
			system('sh ' + GEO_SCRIPT + ' download >/tmp/mb-geo.log 2>&1 &');
			return { status: 'started' };
		},
		geoStatus: function() {
			// runCapture добавляет строку MB_EXIT -> берём первую строку (JSON от geo.sh)
			let line = firstLine(runCapture('sh ' + GEO_SCRIPT + ' status').out);
			let j = (line != '') ? json(line) : null;
			return (type(j) == 'object') ? j : { state: 'idle', geoip: 0, geosite: 0 };
		},
		geoInstall: function(which) {
			// defense-in-depth: whitelist и здесь (which идёт в команду + имя файла)
			if (which != "geoip" && which != "geosite")
				return { ok: false, detail: "bad which" };
			let r = runCapture('sh ' + GEO_SCRIPT + ' install ' + which + ' /tmp/mb-upload-' + which + '.dat 2>&1');
			return { ok: r.ok, detail: firstLine(r.out) };
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
	geo_update:           { args: { geoip_url: '', geosite_url: '' }, call: function(req) { return h.geoUpdate(buildCtx(), req.args); } },
	set_routing:          { args: { direct: '', proxy: '' }, call: function(req) { return h.setRouting(buildCtx(), req.args); } },
	geo_status:           { call: function() { return h.geoStatus(buildCtx()); } },
	geo_install:          { args: { which: '' }, call: function(req) { return h.geoInstall(buildCtx(), req.args); } },
	check_exit:           { args: { domain: '' }, call: function(req) { return h.checkExit(buildCtx(), req.args); } },
};

return { 'monkey-business': methods };
