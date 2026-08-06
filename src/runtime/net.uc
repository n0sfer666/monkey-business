// Всё, что ходит в сеть с устройства: подписка, пинг, эфемерная проба кандидата, проверка выхода.
// Фабрика, а не голые функции: сюда прокидываются запуск команд и рантайм hysteria.

import { readfile, writefile } from 'fs';
import { generateProbe } from '../generator/xray.uc';
import { isHysteria } from '../generator/hysteria.uc';
import { GEO_DIR } from './paths.uc';

function haveCurl(stat_) {
	return stat_('/usr/bin/curl') != null || stat_('/bin/curl') != null;
}

function netRuntime(sh, hysteria, stat_) {
	let shq = sh.shq, runCapture = sh.runCapture;

	// Тело подписки + (если есть curl) заголовок Subscription-Userinfo для трафика.
	// uclient-fetch не умеет сохранять заголовки ответа -> userinfo доступен только с curl.
	function fetchSubscription(url) {
		let bodyf = '/tmp/mb-sub.body', hdrf = '/tmp/mb-sub.hdr';
		system('rm -f ' + bodyf + ' ' + hdrf);
		// тело/заголовки содержат токен/UUID серверов -> umask 077: файлы создаются 0600 сразу,
		// без окна world-readable во время скачивания; подчистка после чтения ниже.
		if (haveCurl(stat_))
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
		let cmd = "pkill -f " + shq(sh.noSelfMatch('xray run -c /tmp/mb-probe.json')) + " 2>/dev/null; " +
			"XRAY_LOCATION_ASSET=" + GEO_DIR + " /usr/bin/xray run -c /tmp/mb-probe.json >/dev/null 2>&1 & P=$!; " +
			"sleep 2; R=fail; " +
			"for u in https://1.1.1.1 https://8.8.8.8; do " +
			"curl -s -4 -o /dev/null -x socks5://127.0.0.1:10809 --max-time 4 \"$u\" && { R=ok; break; }; done; " +
			"kill \"$P\" 2>/dev/null; echo \"PROBE:$R\"";
		let r = runCapture(cmd);
		system('rm -f /tmp/mb-probe.json');
		if (hy)
			hysteria.probeStop();
		return index(r.out, 'PROBE:ok') >= 0;
	}

	function checkExit(domain) {
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
	}

	return {
		fetchSubscription: fetchSubscription,
		tcpPing: tcpPing,
		probeServer: probeServer,
		checkExit: checkExit,
	};
}

export { netRuntime };
