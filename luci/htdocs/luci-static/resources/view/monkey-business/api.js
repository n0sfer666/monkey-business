'use strict';
'require baseclass';
'require rpc';

var SLOW_SECS = 60;

function mb(method, params) {
	return rpc.declare({ object: 'monkey-business', method: method, params: params || [] });
}

function slow(call) {
	return function() {
		var prev = L.env.rpctimeout;
		L.env.rpctimeout = SLOW_SECS;
		try {
			return call.apply(this, arguments);
		} finally {
			L.env.rpctimeout = prev;
		}
	};
}

return baseclass.extend({
	status: mb('status'),
	serviceToggle: mb('service_toggle', [ 'enabled' ]),
	checkExit: mb('check_exit', [ 'domain' ]),
	configApply: mb('config_apply'),
	setMode: mb('set_mode', [ 'mode', 'region' ]),
	setRouting: mb('set_routing', [ 'direct', 'proxy' ]),
	routingCheck: mb('routing_check', [ 'direct', 'proxy' ]),
	serversList: mb('servers_list'),
	serversPing: mb('servers_ping'),
	serverPing: mb('server_ping', [ 'id' ]),
	parseUri: mb('parse_uri', [ 'uri', 'section' ]),
	serverLink: mb('server_link', [ 'section' ]),
	subscriptionUpdate: slow(mb('subscription_update', [ 'sub', 'url' ])),
	subscriptionAdd: slow(mb('subscription_add', [ 'name', 'url' ])),
	subscriptionPing: mb('subscription_ping', [ 'sub' ]),
	subscriptionSelect: mb('subscription_select', [ 'sub' ]),
	serverConnect: mb('server_connect', [ 'id' ]),
	geoStatus: mb('geo_status'),
	geoUpdate: mb('geo_update', [ 'geoip_url', 'geosite_url' ]),
	geoInstall: mb('geo_install', [ 'which' ]),
	hysteriaStatus: mb('hysteria_status'),
	hysteriaInstall: mb('hysteria_install'),
	uciApply: rpc.declare({ object: 'uci', method: 'apply', params: [ 'rollback' ], reject: true })
});
