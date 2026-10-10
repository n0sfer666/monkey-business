'use strict';
'require baseclass';
'require view.monkey-business.model.servers as servers';

var TRANSPORT = { tcp: 'TCP', ws: 'WebSocket', xhttp: 'XHTTP', grpc: 'gRPC', httpupgrade: 'HTTPUpgrade' };
var SECURITY = { reality: 'Reality', tls: 'TLS', none: _('no TLS') };

function errorText(res) {
	var d = res.detail || '';
	switch (res.error) {
	case 'unparseable':           return _('This is not a valid link');
	case 'multiple_links':        return _('Paste one link — %s found. A list belongs in a subscription.').format(d);
	case 'unsupported_scheme':    return _('Protocol %s is not supported').format(d);
	case 'invalid_host':          return _('The address is not valid');
	case 'invalid_port':          return _('The port is not valid');
	case 'missing_uuid':          return _('The link has no UUID');
	case 'invalid_uuid':          return _('The UUID is too long: xray accepts a UUID or any string up to 30 characters');
	case 'missing_password':      return _('The link has no password');
	case 'missing_reality_key':   return _('Reality needs a public key (pbk) — this link has none');
	case 'invalid_reality_key':   return _('The Reality public key is malformed (expected 43 base64url characters)');
	case 'invalid_short_id':      return _('The Reality short ID must be up to 16 hex characters, even length');
	case 'unsupported_security':  return _('Security %s is not supported').format(d);
	case 'unsupported_transport': return _('Transport %s is not supported').format(d);
	case 'flow_needs_tls':        return _('Flow xtls-rprx-vision needs TLS or Reality, not security=none');
	case 'flow_needs_tcp':        return _('Flow xtls-rprx-vision works over TCP only, not %s').format(d);
	case 'unsupported_flow':      return _('Flow %s is not supported').format(d);
	case 'unsupported_obfs':      return _('Obfuscation %s is not supported').format(d);
	case 'missing_obfs_password': return _('Obfuscation salamander needs a password');
	}
	return _('This link cannot be used');
}

function warnings(res) {
	return (res.warnings || []).map(function(w) {
		if (w === 'insecure')
			return _('certificate check is disabled (insecure=1)');
		if (w === 'duplicate')
			return _('this server is already in the list as “%s”').format(res.duplicate || '');
		return w;
	});
}

function verdict(res) {
	if (res == null || res.error === 'empty')
		return { level: 'idle', text: _('vless:// or hy2:// — one link') };
	if (!res.ok)
		return { level: 'error', text: errorText(res) };
	var warn = warnings(res);
	if (warn.length)
		return { level: 'warn', text: _('Valid, but %s').format(warn.join('; ')) };
	return { level: 'ok', text: _('Valid link') };
}

function chips(s) {
	if (s == null)
		return [];
	if (s.protocol === 'hysteria2')
		return [ 'Hysteria2', servers.endpoint(s), s.obfs_type || _('no obfs') ].concat(s.mport ? [ _('ports %s').format(s.mport) ] : []);
	return [ 'VLESS', servers.endpoint(s), SECURITY[s.security] || s.security, TRANSPORT[s.tr_type] || s.tr_type ]
		.concat(s.flow ? [ '+' + s.flow ] : []);
}

return baseclass.extend({
	verdict: verdict,
	chips: chips
});
