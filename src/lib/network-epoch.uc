// Kernel use/ref counters are traffic statistics, never a WAN epoch.
function routeIdentity(ipv4, ipv6, local, addresses, links) {
	let routes = [], interfaces = {};
	for (let line in split(ipv4 || '', '\n')) {
		let f = split(trim(line), /[[:space:]]+/);
		if (length(f) < 11 || f[0] == 'Iface') continue;
		push(routes, [4, f[0], f[1], f[2], f[3], f[6], f[7]]); interfaces[f[0]] = true;
	}
	for (let line in split(ipv6 || '', '\n')) {
		let f = split(trim(line), /[[:space:]]+/);
		if (length(f) != 10 || (hex(f[8]) & 0x01000000)) continue;
		push(routes, [6, f[0], f[1], f[2], f[3], f[4], f[5], f[8], f[9]]); interfaces[f[9]] = true;
	}
	sort(routes, function(a, b) { let x = sprintf('%J', a), y = sprintf('%J', b); return x == y ? 0 : x < y ? -1 : 1; });
	return { routes: routes, local: sort(local || []), addresses: sort(filter(split(addresses || '', '\n'), function(line) { return length(line) > 0; })),
		interfaces: sort(keys(interfaces)), links: links || {} };
}
export { routeIdentity };
