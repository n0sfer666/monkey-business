// Independent exit-IP/leak check. It never increments VPN availability streaks.
import { readfile, lstat, unlink } from 'fs';
import { ownsListener } from './listener.uc';
import { diagnosticCredentials, diagnosticPort } from '../lib/diagnostic.uc';
import { listenerOwner } from './engine-listener.uc';
import { privateDirectory, atomicPrivate, nonce } from './private-store.uc';
function probeExit(sh, proxy, domain, directory) {
	domain = domain || 'api.ip.sb';
	if (type(domain) != 'string' || length(domain) > 253 || match(domain, /^[A-Za-z0-9.-]+$/) == null)
		return { error: 'invalid_exit_host' };
	let forced = type(proxy) == 'object' ? proxy : null;
	if (forced != null && (!diagnosticPort(forced.port) || !diagnosticCredentials(forced.credentials) || !ownsListener(forced.pid, forced.identity, forced.port))) return { error: 'live_listener_missing' };
	if (proxy && forced == null && listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 10808) == null)
		return { error: 'live_listener_missing' };
	directory = directory || '/tmp/mb-runtime';
	if (!privateDirectory(directory)) return { error: 'unsafe_probe_directory' };
	let base = directory + '/exit-' + nonce(), result;
	try {
		let url = 'https://' + domain + (domain == 'api.ip.sb' ? '/geoip' : '/json?fields=status,message,query,country,countryCode');
		let config = 'url = ' + sprintf('%J', url) + '\noutput = ' + sprintf('%J', base + '.body') + '\n' +
			(proxy ? 'proxy = "socks5h://127.0.0.1:' + (forced != null ? forced.port : 10808) + '"\nnoproxy = ""\n' +
				(forced != null ? 'proxy-user = ' + sprintf('%J', forced.credentials.user + ':' + forced.credentials.pass) + '\n' : '') : 'proxy = ""\n');
		if (!atomicPrivate(base + '.conf', config)) die('write_failed');
		let fetched = sh.runCapture('umask 077; timeout 8 curl --disable --globoff -fsS --proto \'=https\' --max-time 6 ' +
			'--max-filesize 4096 --config ' + base + '.conf 2>/dev/null');
		let st = lstat(base + '.body');
		if (!fetched.ok || st == null || st.size > 4096) die('fetch_failed');
		let body = json(readfile(base + '.body')), bytes = iptoarr(body.ip || body.query || '');
		if (bytes == null) die('invalid_exit_response');
		result = { probe: domain, ip: arrtoip(bytes), country: substr(body.country || body.country_name || '', 0, 80),
			code: match(body.country_code || body.countryCode || '', /^[A-Z]{2}$/) != null ? (body.country_code || body.countryCode) : '' };
	} catch (e) { result = { error: 'exit_probe_failed' }; }
	unlink(base + '.conf'); unlink(base + '.body'); return result;
}
export { probeExit };
