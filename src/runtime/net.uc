// Всё, что ходит в сеть с устройства: подписка, пинг, эфемерная проба кандидата, проверка выхода.
// Фабрика, а не голые функции: сюда прокидываются запуск команд и рантайм hysteria.

import { readfile, lstat, unlink, rmdir } from 'fs';
import { privateDirectory, atomicPrivate, nonce } from './private-store.uc';
import { probeExit } from './exit-probe.uc';
import { acquireSlots, releaseSlots } from './probe-slots.uc';

function netRuntime(sh, hysteria, stat_) {
	let runCapture = sh.runCapture;

	// Тело подписки + (если есть curl) заголовок Subscription-Userinfo для трафика.
	// uclient-fetch не умеет сохранять заголовки ответа -> userinfo доступен только с curl.
	function fetchSubscription(url) {
		if (type(url) != 'string' || length(url) > 8192 || match(url, /^https:\/\//i) == null ||
			match(url, /[[:space:][:cntrl:]]/) != null) return null;
		let base = '/tmp/mb-runtime/sub-' + nonce();
		if (!privateDirectory('/tmp/mb-runtime') || !privateDirectory(base)) return null;
		let result = null;
		try {
			let config = 'url = ' + sprintf('%J', url) + '\noutput = ' + sprintf('%J', base + '/body') +
				'\ndump-header = ' + sprintf('%J', base + '/headers') + '\n';
			if (!atomicPrivate(base + '/curl.conf', config)) die('write_failed');
			let downloaded = runCapture('umask 077; timeout 28 curl --disable --globoff -fsSL --proto \'=https\' --proto-redir \'=https\' ' +
				'--max-redirs 5 --max-time 25 --max-filesize 2097152 --config ' + base + '/curl.conf 2>/dev/null');
			let body = lstat(base + '/body'), headers = lstat(base + '/headers');
			if (!downloaded.ok || body == null || body.size < 1 || body.size > 2097152 ||
				(headers != null && headers.size > 262144)) die('fetch_failed');
			let userinfo = '';
			for (let line in split(readfile(base + '/headers') || '', '\n'))
				if (index(lc(line), 'subscription-userinfo:') == 0) userinfo = trim(substr(line, index(line, ':') + 1));
			result = { body: readfile(base + '/body'), userinfo: userinfo };
		} catch (e) {}
		for (let file in ['curl.conf', 'body', 'headers']) unlink(base + '/' + file);
		rmdir(base); return result;
	}

	return {
		fetchSubscription: fetchSubscription,
		checkExit: function(domain) {
			let slots = acquireSlots('manual', true);
			if (slots == null) return { error: 'busy' };
			let result = probeExit(sh, true, domain); releaseSlots(slots); return result;
		},
	};
}

export { netRuntime };
