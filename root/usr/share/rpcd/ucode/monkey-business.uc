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
import { generateProbe } from '/usr/share/rpcd/ucode/lib/monkey-business/generator/xray.uc';
import * as hy from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/hysteria.uc';
import { isHysteria } from '/usr/share/rpcd/ucode/lib/monkey-business/generator/hysteria.uc';
import { hysteriaRuntime } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/hysteria.uc';

const CONFIG = 'monkey-business';
const CONF_DIR = '/etc/monkey-business';
const XRAY_CONF = CONF_DIR + '/xray.json';
const GEO_DIR = '/usr/share/xray';
const GEO_SCRIPT = '/usr/share/monkey-business/geo.sh';
const WD_STATE = '/tmp/mb-watchdog/state';
// Активный сервер — рантайм-состояние, а не выбор пользователя (выбора в UI нет, приоритет задаётся
// порядком секций). Раньше он лежал в uci.selected.server, и КАЖДЫЙ автофейловер делал commit,
// переписывая /etc/config/monkey-business целиком; в застрявшем цикле — раз в BACKOFF, круглые
// сутки. Теперь это один файл рядом с xray.json, и пишется он только при РЕАЛЬНОЙ смене тега.
const ACTIVE_FILE = CONF_DIR + '/active';

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

// Объявление ПОСЛЕ runCapture: ucode не хойстит, ссылка на ещё не определённую функцию упала бы
// на загрузке плагина.
const hysteria = hysteriaRuntime(runCapture);

// Служебный маркер runCapture — не часть вывода команды. Без вычистки команда, ничего не
// напечатавшая, отдавала наружу буфер из одной строки "MB_EXIT:0", и он утекал в UI как
// «последнее событие» / detail ошибки.
function stripExit(s) {
	let keep = [];
	for (let l in split((s != null) ? s : '', '\n'))
		if (index(l, 'MB_EXIT:') != 0)
			push(keep, l);
	return join('\n', keep);
}

// pgrep/pkill -f матчат и промежуточный `sh -c <вся команда>` из popen(): паттерн лежит в его же
// cmdline. Из-за этого pkill в probeServer убивал СОБСТВЕННЫЙ шелл ещё до старта xray (проба
// всегда падала -> «no working failover server»), а pgrep рапортовал «сервис жив» всегда.
// `[x]ray…` — регексп, который матчит боевой процесс, но не текст самой команды.
function noSelfMatch(cmdline) {
	return '[' + substr(cmdline, 0, 1) + ']' + substr(cmdline, 1);
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
	for (let key in ["transport", "reality", "alpn", "obfs"]) {
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

// Размер, а не только наличие: оборванная закачка оставляет .dat в пару килобайт — проверка
// на null проходит, а xray потом падает на старте с невнятной ошибкой парсинга гео-базы.
function geoPresent() {
	let ip = stat(GEO_DIR + '/geoip.dat'), site = stat(GEO_DIR + '/geosite.dat');
	return ip != null && site != null && ip.size > 0 && site.size > 0;
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
	// busybox nc на устройстве без флагов -z/-w -> curl: %{time_connect} = время TCP-connect (сек);
	// awk даёт целые мс (0 если connect не состоялся). server.address — внешний вход -> shq.
	let cmd = 'curl -s -o /dev/null --connect-timeout 2 --max-time 4 -w "%{time_connect}" ' +
		'http://' + shq(server.address) + ':' + int(server.port) +
		" 2>/dev/null | awk '{printf \"%d\", ($1+0)*1000}'";
	let r = runCapture(cmd);
	let ms = int(split(r.out, 'MB_EXIT')[0]);
	return (ms > 0) ? ms : null;
}

// Эфемерная проба кандидата для failover: временный xray (socks 10809) -> реальный проход трафика
// через туннель (curl к иностранному IP), затем kill. Боевой сервис/kill-switch не трогаются (pkill
// матчит только /tmp/mb-probe.json, не /etc/monkey-business/xray.json). true = сервер живой.
function probeServer(global, dns, server) {
	// hysteria-кандидат: под пробу поднимается свой эфемерный клиент на 10811, и xray-проба ходит
	// через него. Нет бинаря — кандидат считается нерабочим (иначе failover «выбрал» бы сервер,
	// который заведомо не поднимется).
	let hy = isHysteria(server);
	if (hy && !hysteria.probeStart(server))
		return false;
	let cfg = generateProbe({
		global: global, dns: dns, server: server, probe_port: 10809,
		hysteria_socks_port: hysteria.PROBE_SOCKS,
	});
	writefile('/tmp/mb-probe.json', sprintf('%.J', cfg));
	let sh = "pkill -f " + shq(noSelfMatch('xray run -c /tmp/mb-probe.json')) + " 2>/dev/null; " +
		"XRAY_LOCATION_ASSET=" + GEO_DIR + " /usr/bin/xray run -c /tmp/mb-probe.json >/dev/null 2>&1 & P=$!; " +
		"sleep 2; R=fail; " +
		"for u in https://1.1.1.1 https://8.8.8.8; do " +
		"curl -s -4 -o /dev/null -x socks5://127.0.0.1:10809 --max-time 4 \"$u\" && { R=ok; break; }; done; " +
		"kill \"$P\" 2>/dev/null; echo \"PROBE:$R\"";
	let r = runCapture(sh);
	system('rm -f /tmp/mb-probe.json');
	if (hy)
		hysteria.probeStop();
	return index(r.out, 'PROBE:ok') >= 0;
}

// Валидирует конфиг реальным xray, при успехе устанавливает + поднимает сервис.
// Возврат: строка-ошибка | null(успех).
//
// Установка атомарная: пишем в соседний .tmp на ТОМ ЖЕ разделе, валидируем именно тот файл,
// что ляжет на место (а не /tmp-копию), и только потом rename. Раньше обрыв на writefile
// оставлял обрезанный xray.json, а `restart` всё равно звался -> сервис не поднимался.
// intentOn=true: reload идёт с MB_INTENT=1 — init-скрипт поднимается, не глядя на ещё не
// выставленный тумблер. Нужен только пути включения (service_toggle); остальные вызовы обязаны
// упираться в гейт, иначе config_apply при выключенном VPN снова поднимал бы туннель молча.
function applyConfig(jsonStr, intentOn) {
	let reload = (intentOn ? 'MB_INTENT=1 ' : '') + '/etc/init.d/monkey-business reload >/dev/null 2>&1';
	system('mkdir -p ' + CONF_DIR);
	if (!geoPresent())
		return 'geo databases missing — press "Update geo databases" on the Dashboard first';

	// Байт-в-байт тот же конфиг — не трогаем карту вообще. Это не микрооптимизация: в фазе `down`
	// watchdog зовёт config_apply раз в BACKOFF, а когда рабочих серверов нет, selectWorking каждый
	// раз возвращает один и тот же servers[0] -> без этой проверки один и тот же файл ложился бы на
	// SD 144 раза в сутки. Валидацию тоже пропускаем: этот файл уже прошёл её, когда его писали.
	if (readfile(XRAY_CONF) == jsonStr) {
		system(reload);
		system('rm -f ' + WD_STATE);
		return null;
	}

	// Расширение .json обязательно: xray выбирает парсер по filepath.Ext(), и `-test -c *.tmp`
	// провалился бы на валидном конфиге.
	let tmp = CONF_DIR + '/.xray.new.json';
	if (writefile(tmp, jsonStr) != length(jsonStr)) {
		system('rm -f ' + tmp);
		return 'failed to write config (disk full?)';
	}
	let v = runCapture('xray run -test -c ' + tmp + ' 2>/tmp/mb-xray.err');
	if (!v.ok) {
		let err = readfile('/tmp/mb-xray.err');
		let msg = firstLine(err != null ? err : v.out);
		system('rm -f ' + tmp);
		return (msg != '') ? msg : 'xray config validation failed';
	}
	// Без sync: rename в ext4 и так атомарен относительно журнала, а принудительный сброс на каждый
	// apply — это read-modify-write сегмента FTL ради данных, которые ядро всё равно допишет само.
	if (!runCapture('mv ' + tmp + ' ' + XRAY_CONF).ok) {
		system('rm -f ' + tmp);
		return 'failed to install config';
	}

	// НЕ restart: stop_service гонит flush.sh и снимает kill-switch, а окно до подъёма xray —
	// это утечка LAN в открытую сеть. reload_service переобъявляет инстанс, procd видит смену
	// хеша файла-триггера (procd_set_param file $CONF) и перезапускает только процесс xray.
	system(reload);
	// Фаза watchdog описывает СТАРЫЙ конфиг; оставленный `down` заставил бы UI врать
	// «Disabled by watchdog» сразу после успешного применения.
	system('rm -f ' + WD_STATE);
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
			let sel = readfile(ACTIVE_FILE);
			sel = (sel != null) ? trim(sel) : '';
			let found = null;
			for (let s in loadServers(cursor))
				if (s.tag == sel)
					found = s;
			return found;
		},
		// Атомарно и с проверкой: на ro-remounted корне (ровно то состояние, против которого весь
		// этот модуль) молчаливый провал записи оставил бы UI с «Server: none» без единого следа.
		setSelected: function(tag) {
			let cur = readfile(ACTIVE_FILE);
			let want = tag + '\n';
			if (cur == want)
				return;
			system('mkdir -p ' + CONF_DIR);
			let tmp = CONF_DIR + '/.active.new';
			if (writefile(tmp, want) != length(want) || !runCapture('mv ' + tmp + ' ' + ACTIVE_FILE).ok) {
				system('rm -f ' + tmp);
				system('logger -t mb-event ' + shq('rpcd: cannot record active server (rootfs read-only?)'));
			}
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
		probeServer: function(s) { return probeServer(loadSection(cursor, 'global'), loadSection(cursor, 'dns'), s); },
		// Каждая проба — до ~10с. Без потолка 7 серверов = ~70с, что дольше ubus-таймаута:
		// вызов рвался, watchdog читал это как «рабочих серверов нет» и уходил в down,
		// хотя rpcd на той стороне доходил до конца и переключался.
		// 0/не задано = перебирать ВЕСЬ список. Жёсткий дефолт вроде 3 при 7 серверах делал
		// рабочий сервер на 4-й позиции недостижимым ни для watchdog, ни для «Turn on».
		failoverCap: function() {
			let v = int(cursor.get(CONFIG, 'global', 'failover_cap') || 0);
			return (v > 0) ? v : 0;
		},
		watchdogPhase: function() {
			let raw = readfile(WD_STATE);
			if (raw == null)
				return null;
			let m = match(raw, /WD_PHASE=([a-z]+)/);
			return (m != null) ? m[1] : null;
		},
		// Тег mb-event, а не monkey-business: последним под общим тегом почти всегда оказывалась
		// служебная строка apply.sh/flush.sh («tproxy firewall flushed») из init.d, а не причина
		// отказа — а в фазе down init.d дёргается каждый тик.
		lastEvent: function() {
			let r = runCapture('logread -e mb-event 2>/dev/null | tail -n 1');
			return firstLine(stripExit(r.out));
		},
		applyConfig: function(jsonStr, intentOn) { return applyConfig(jsonStr, intentOn); },
		stopService: function() { system('/etc/init.d/monkey-business stop'); },
		serviceRunning: function() {
			// Матч по cmdline боевого конфига: `pidof xray` считал живым и эфемерную пробу
			// failover (/tmp/mb-probe.json), и чужой xray из стокового пакета -> UI врал
			// «Connected» при отсутствующем туннеле. pgrep -x не матчит comm в этой сборке
			// BusyBox, а -f (как в pkill выше) работает.
			// hysteria (когда активен именно он) — часть того же туннеля: живой xray с мёртвым
			// клиентом это не «Connected», а трафик в закрытый socks.
			return index(runCapture('pgrep -f ' + shq(noSelfMatch('xray run -c ' + XRAY_CONF)) +
				' >/dev/null && echo up').out, 'up') >= 0 && hysteria.running();
		},
		// Возврат = легло ли намерение в UCI: на read-only rootfs commit не проходит, а туннель к
		// этому моменту уже поднят обходом гейта — вызывающий обязан узнать и свернуть его.
		setEnabled: function(on) {
			cursor.set(CONFIG, 'global', 'enabled', on ? '1' : '0');
			return cursor.commit(CONFIG) === true;
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
		// Возврат = легло ли в UCI: файрвол (init.d) читает пару из UCI, а не из памяти курсора, и
		// незаписанный на read-only rootfs режим дал бы «применили» при неизменившемся обходе.
		setMode: function(mode, region) {
			cursor.set(CONFIG, 'global', 'routing_mode', mode);
			cursor.set(CONFIG, 'global', 'local_region', region);
			return cursor.commit(CONFIG) === true;
		},
		// Обход ФАКТИЧЕСКИ включён = в prerouting стоит правило по сету mb_ru4 (его ставит apply.sh
		// только при MB_DIRECT_BYPASS=1). Читаем цепочку, а не сет: в mb_ru4 тысячи RU-CIDR, а
		// status опрашивается раз в 5с. Нет таблицы (VPN выключен) — nft молчит в stderr, и это
		// честный false.
		directBypassActive: function() {
			return index(runCapture('nft list chain inet monkey_business prerouting 2>/dev/null').out,
				'mb_ru4') >= 0;
		},
		hysteriaInstalled: function() { return hysteria.installed(); },
		applyHysteria: function(jsonStr) { return hysteria.apply(jsonStr); },
		hysteriaStatus: function() { return hysteria.status(); },
		hysteriaInstall: function() { return hysteria.install(); },
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
			let line = firstLine(stripExit(runCapture('sh ' + GEO_SCRIPT + ' status').out));
			let j = (line != '') ? json(line) : null;
			return (type(j) == 'object') ? j : { state: 'idle', geoip: 0, geosite: 0 };
		},
		geoInstall: function(which) {
			// defense-in-depth: whitelist и здесь (which идёт в команду + имя файла)
			if (which != "geoip" && which != "geosite")
				return { ok: false, detail: "bad which" };
			let r = runCapture('sh ' + GEO_SCRIPT + ' install ' + which + ' /tmp/mb-upload-' + which + '.dat 2>&1');
			return { ok: r.ok, detail: firstLine(stripExit(r.out)) };
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
	set_mode:             { args: { mode: '', region: '' }, call: function(req) { return h.setMode(buildCtx(), req.args); } },
	geo_status:           { call: function() { return h.geoStatus(buildCtx()); } },
	geo_install:          { args: { which: '' }, call: function(req) { return h.geoInstall(buildCtx(), req.args); } },
	check_exit:           { args: { domain: '' }, call: function(req) { return h.checkExit(buildCtx(), req.args); } },
	hysteria_status:      { call: function() { return hy.hysteriaStatus(buildCtx()); } },
	hysteria_install:     { call: function() { return hy.hysteriaInstall(buildCtx()); } },
};

return { 'monkey-business': methods };
