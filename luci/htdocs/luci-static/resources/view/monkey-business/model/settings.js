'use strict';
'require baseclass';

function opts(list) {
	return list.map(function(v) { return { value: v, label: v }; });
}

return baseclass.extend({
	sections: [ {
		sid: 'global',
		title: _('General'),
		hint: _('Routing mode and region live on the Dashboard'),
		rows: [
			{ opt: 'kill_switch', kind: 'flag', def: '1', label: _('Kill-switch'),
				hint: _('Drop LAN traffic instead of leaking it direct when the tunnel does not carry it') },
			{ opt: 'ipv6_block', kind: 'flag', def: '1', label: _('Block IPv6'),
				hint: _('Clients get no IPv6, so nothing leaks around the IPv4 tunnel') },
			{ opt: 'tproxy_port', kind: 'text', def: '12345', label: _('TPROXY port'), hint: _('Change only on conflicts'),
				mono: true, width: '80px', layout: 'short', check: 'port' },
			{ opt: 'log_level', kind: 'select', def: 'warning', label: _('Log level'), width: '120px', layout: 'pick',
				options: opts([ 'none', 'error', 'warning', 'info', 'debug' ]) }
		]
	}, {
		sid: 'dns',
		title: _('DNS'),
		hint: _('Split: local domains direct, foreign over DoH in the tunnel'),
		rows: [
			{ opt: 'mode', kind: 'select', def: 'split', label: _('DNS mode'), width: '190px', layout: 'pick',
				options: [ { value: 'split', label: _('Split (recommended)') }, { value: 'doh', label: _('All over DoH') } ] },
			{ opt: 'direct_dns', kind: 'text', def: '77.88.8.8', label: _('Direct DNS'),
				hint: _('Resolver for local-region domains'), mono: true, layout: 'wide' },
			{ opt: 'doh_url', kind: 'text', def: 'https://1.1.1.1/dns-query', label: _('DoH URL'),
				hint: _('Everything routed through the VPN resolves here'), mono: true, layout: 'wide' }
		]
	}, {
		sid: 'anti_dpi',
		title: _('Anti-DPI'),
		hint: _('How the tunnel disguises itself'),
		rows: [
			{ opt: 'default_fingerprint', kind: 'select', def: 'chrome', label: _('TLS fingerprint'),
				hint: _('Mimic a real browser (uTLS)'), width: '120px', layout: 'pick',
				options: opts([ 'chrome', 'firefox', 'safari', 'edge', 'random' ]) },
			{ opt: 'xhttp_padding', kind: 'flag', def: '0', label: _('XHTTP padding'),
				hint: _('Random padding hides traffic size patterns') }
		]
	} ]
});
