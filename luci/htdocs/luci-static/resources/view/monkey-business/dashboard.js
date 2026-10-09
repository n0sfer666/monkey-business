'use strict';
'require view';
'require view.monkey-business.api as api';
'require uci';
'require view.monkey-business.routing as mbroute';
'require view.monkey-business.hysteria as mbhy';
'require view.monkey-business.status as mbstatus';
'require view.monkey-business.traffic as mbtraffic';
'require view.monkey-business.splitlists as mbsplit';
'require view.monkey-business.geo as mbgeo';
'require view.monkey-business.serverlist as mbservers';

return view.extend({
	load: function() {
		// каждый вызов с фолбэком: один упавший ubus-метод не должен ронять всю вьюшку
		return Promise.all([
			api.status().catch(function() { return {}; }),
			api.serversList().catch(function() { return {}; }),
			uci.load('monkey-business').catch(function() { return null; }),
			api.geoStatus().catch(function() { return {}; }),
			api.hysteriaStatus().catch(function() { return {}; })
		]);
	},

	render: function(data) {
		var st = data[0] || {};
		var servers = (data[1] || {}).servers || [];
		var geo = data[3] || {};
		return E('div', {}, [
			mbtraffic.render(st),
			mbstatus.render(st),
			mbroute.render(),
			mbsplit.render(),
			mbgeo.render(geo),
			mbhy.render(data[4] || {}),
			mbservers.render(servers, st)
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
