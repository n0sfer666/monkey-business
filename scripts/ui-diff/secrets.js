const fs = require('fs');
const path = require('path');
const { escape } = require('./regex');

const LINK = /(vless|vmess|trojan|ss|hysteria2?|hy2|tuic):\/\/\S+/gi;
const DEFAULT_FILE = '.context/notes/vpnon-sub.local';

function loadSecret(root) {
	const file = path.resolve(root, process.env.MB_VM_SUB_FILE || DEFAULT_FILE);
	let text = '';
	try { text = fs.readFileSync(file, 'utf8'); } catch (e) { text = ''; }
	const m = text.match(/https?:\/\/\S+/);
	if (!m) throw new Error('no subscription URL to scrub: ' + path.relative(root, file) + ' (MB_VM_SUB_FILE)');
	return m[0];
}

function hostOf(secret) {
	try {
		return new URL(secret).hostname.toLowerCase();
	} catch (e) {
		return null;
	}
}

function makeScrub(secret) {
	const host = hostOf(secret);
	const byHost = host ? new RegExp('\\S*' + escape(host) + '(\\S*)', 'gi') : null;
	return value => {
		let out = String(value).split(secret).join(`<SUB_URL:${secret.length}>`);
		if (byHost) out = out.replace(byHost, (m, tail) => /^:\d+$/.test(tail) ? `<HOST:${m.length - tail.length}>${tail}` : `<SUB_URL:${m.length}>`);
		return out.replace(LINK, m => `<LINK:${m.length}>`);
	};
}

module.exports = { loadSecret, hostOf, makeScrub, LINK_SOURCE: LINK.source };
