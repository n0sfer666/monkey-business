'use strict';
'require view';
'require poll';
'require uci';
'require view.monkey-business.api as api';
'require view.monkey-business.store as store';
'require view.monkey-business.pingtext as pingtext';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.tabs as tabs';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.dash.status as status';
'require view.monkey-business.dash.serverlist as serverlist';
'require view.monkey-business.dash.routing as routing';
'require view.monkey-business.dash.components as components';
'require view.monkey-business.dash.rules as rules';
'require view.monkey-business.dash.geosheet as geosheet';

style.add('dash', [
	'.mb.mb-dash [hidden]{display:none!important}',
	'.mb .mb-dash-grow{flex-grow:1}',
	'.mb .mb-dash-narrow{display:none}',
	'.mb .mb-dash-grid{display:grid;grid-template-columns:minmax(0,1.75fr) minmax(0,1fr);gap:14px}',
	'.mb .mb-dash-side{display:flex;flex-direction:column;gap:14px;min-width:0}',
	style.STACK + '{.mb .mb-dash-grid{grid-template-columns:minmax(0,1fr)}}',
	style.MOBILE + '{',
	'.mb .mb-dash-wide{display:none}',
	'.mb .mb-dash-narrow{display:inline}',
	'.mb .mb-dash-grid,.mb .mb-dash-side{gap:12px}',
	'}'
].join(''));

function line(cur, servers) {
	var s = model.byId(servers, cur.server_id);
	var parts = [ cur.server || '' ];
	if (s)
		parts.push(model.protocol(s));
	if (s && s.latency_ms != null)
		parts.push(pingtext.ms(s.latency_ms));
	if (cur.reserve)
		parts.push(_('reserve'));
	return parts.filter(Boolean).join(' · ');
}

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load: function() {
		return Promise.all([
			api.status().catch(function() { return {}; }),
			api.serversList().catch(function() { return {}; }),
			uci.load(store.CONF).catch(function() { return null; }),
			api.geoStatus().catch(function() { return {}; }),
			api.hysteriaStatus().catch(function() { return {}; })
		]);
	},

	render: function(data) {
		var readonly = !L.hasViewPermission();
		var servers = (data[1] || {}).servers || [];
		var geo = data[3] || {};
		var card, list, route, comps;

		function paint(cur) {
			card.update(cur, geo, line(cur, servers));
			list.update(servers, cur);
		}

		function refresh() {
			return Promise.all([ api.status(), api.serversList(), api.geoStatus().catch(function() { return geo; }) ]).then(function(r) {
				servers = (r[1] || {}).servers || servers;
				geo = r[2] || geo;
				comps.geo(geo);
				paint(r[0] || {});
			}).catch(function() { card.stale(); });
		}

		function changed() {
			uci.unload(store.CONF);
			return Promise.all([ refresh(), uci.load(store.CONF).then(function() { route.update(); }) ]);
		}

		function openGeo() {
			geosheet.open({ geo: geo, onChanged: changed });
		}

		function openRules() {
			rules.open({
				direct: uci.get(store.CONF, 'global', 'custom_direct') || '',
				proxy: uci.get(store.CONF, 'global', 'custom_proxy') || '',
				onSaved: changed
			});
		}

		card = status.render(data[0] || {}, { readonly: readonly, onGeo: openGeo, onDone: changed });
		list = serverlist.render({ readonly: readonly, onChanged: changed });
		route = routing.render({ readonly: readonly, onEdit: openRules, onChanged: changed });
		comps = components.render({ readonly: readonly, onGeo: openGeo });
		comps.geo(geo);
		comps.hysteria(data[4] || {});
		paint(data[0] || {});

		poll.add(function() {
			return api.status().then(paint).catch(function() { card.stale(); });
		}, 5);

		return E('div', { 'class': 'mb mb-view mb-dash' }, [
			tabs.render('dashboard'),
			card.node,
			E('div', { 'class': 'mb-dash-grid' }, [
				list.node,
				E('div', { 'class': 'mb-dash-side' }, [ route.node, comps.node ])
			])
		]);
	}
});
