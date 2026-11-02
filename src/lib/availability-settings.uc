import { publicIpv4 } from './corporate.uc';

const DEFAULT_TARGETS = [
	{ url: 'https://www.gstatic.com/generate_204', expected_status: 204 },
	{ url: 'https://cp.cloudflare.com/generate_204', expected_status: 204 }
];
function unsafeUrl(value) {
	for (let i = 0; i < length(value); i++) {
		let byte = ord(value, i);
		if (byte <= 32 || byte == 127 || byte == 92) return true;
	}
	return false;
}
function normalizeTarget(raw) {
	if (type(raw) != 'object' || type(raw.url) != 'string' || length(raw.url) > 1024 ||
		unsafeUrl(raw.url) || index(raw.url, '#') >= 0 ||
		(raw.expected_status !== 200 && raw.expected_status !== 204)) return { error: 'invalid_target' };
	let parts = match(raw.url, /^https:\/\/([^\/?#]+)([^#]*)$/i);
	if (parts == null || index(parts[1], '@') >= 0) return { error: 'invalid_https_url' };
	let authority = match(parts[1], /^([A-Za-z0-9.-]+)(:([0-9]{1,5}))?$/);
	let ipv6 = match(parts[1], /^\[([0-9a-f:]+)\](:([0-9]{1,5}))?$/i);
	if (authority == null && ipv6 == null) return { error: 'invalid_host' };
	let host = lc((authority || ipv6)[1]);
	if (substr(host, -1) == '.') host = substr(host, 0, -1);
	if (!length(host) || length(host) > 253) return { error: 'invalid_host' };
	if (ipv6 != null) {
		let bytes = iptoarr(host);
		if (bytes == null || length(bytes) != 16 || (bytes[0] & 0xe0) != 0x20 ||
			(bytes[0] == 0x20 && bytes[1] == 1 && bytes[2] < 2) ||
			(bytes[0] == 0x20 && bytes[1] == 1 && bytes[2] == 0x0d && bytes[3] == 0xb8) ||
			(bytes[0] == 0x3f && (bytes[1] & 0xf0) == 0xf0)) return { error: 'public_ip_required' };
		host = arrtoip(bytes);
	} else if (match(host, /^[0-9.]+$/) != null) {
		if (!publicIpv4(host)) return { error: 'public_ip_required' };
	} else {
		if (index(host, '.') < 0 || match(split(host, '.')[-1], /^[0-9]+$/) != null) return { error: 'invalid_host' };
		for (let label in split(host, '.'))
			if (length(label) > 63 || match(label, /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) == null)
				return { error: 'invalid_host' };
	}
	let port = (authority || ipv6)[3] == null ? 443 : int((authority || ipv6)[3]);
	if (port < 1 || port > 65535) return { error: 'invalid_port' };
	let urlHost = ipv6 != null ? '[' + host + ']' : host;
	let path = parts[2] == '' ? '/' : parts[2];
	if (substr(path, 0, 1) == '?') path = '/' + path;
	return { target: { url: 'https://' + urlHost + (port == 443 ? '' : ':' + port) + path,
		expected_status: raw.expected_status }, host: host };
}
function normalizeTargets(raw) {
	if (type(raw) != 'array' || length(raw) != 2) return { errors: [{ code: 'two_targets_required' }] };
	let targets = [], hosts = [], errors = [];
	for (let i = 0; i < 2; i++) {
		let result = normalizeTarget(raw[i]);
		if (result.error != null) push(errors, { index: i, code: result.error });
		else { push(targets, result.target); push(hosts, result.host); }
	}
	if (!length(errors) && hosts[0] == hosts[1]) push(errors, { index: 1, code: 'distinct_hosts_required' });
	return { targets: targets, errors: errors };
}
function curlConfig(target, diagnostic, output) {
	// Only normalized URLs, fixed internal paths and generated credentials are accepted.
	let checked = normalizeTarget(target);
	if (checked.error != null) die(checked.error);
	function quote(value) { return '"' + replace(replace(value, '\\', '\\\\'), '"', '\\"') + '"'; }
	return 'silent\nshow-error\ngloboff\nmax-time = 6\nconnect-timeout = 6\nmax-filesize = 4096\n' +
		'proto = "=https"\nproxy = ' + quote('socks5h://127.0.0.1:' + diagnostic.port) + '\n' +
		'noproxy = ""\nproxy-user = ' + quote(diagnostic.credentials.user + ':' + diagnostic.credentials.pass) + '\n' +
		'url = ' + quote(checked.target.url) + '\noutput = ' + quote(output) + '\n' +
		'write-out = "%{http_code} %{time_total}"\n';
}
export { DEFAULT_TARGETS, normalizeTarget, normalizeTargets, curlConfig };
