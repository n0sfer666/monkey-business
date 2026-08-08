'use strict';
'require baseclass';
'require rpc';
'require ui';
'require uci';

// Пользовательские списки direct/proxy для сплит-режимов.
var callSetRouting = rpc.declare({ object: 'monkey-business', method: 'set_routing', params: ['direct', 'proxy'] });

function notifyApplied(res) {
	if (res && res.error)
		ui.addNotification(null, E('p', _('Apply failed: ') + res.error), 'warning');
	else if (res && res.skipped == 'disabled')
		ui.addNotification(null, E('p', _('Rules saved. The VPN is off — they will apply when you turn it on.')), 'info');
	else
		ui.addNotification(null, E('p', _('Routing rules applied.')), 'info');
}

return baseclass.extend({
	render: function() {
		var direct = uci.get('monkey-business', 'global', 'custom_direct') || '';
		var proxy = uci.get('monkey-business', 'global', 'custom_proxy') || '';

		var taDirect = E('textarea', {
			'rows': 6, 'style': 'width:100%;max-width:480px',
			'placeholder': 'example.com\n*.frontier.com\n10.0.0.0/8\ngeosite:category-ru\ngeoip:ru'
		}, [ direct ]);
		var taProxy = E('textarea', {
			'rows': 6, 'style': 'width:100%;max-width:480px',
			'placeholder': 'blocked.example\n*.netflix.com\ngeosite:google\ngeoip:netflix'
		}, [ proxy ]);

		var save = E('button', {
			'class': 'btn cbi-button cbi-button-apply',
			'click': ui.createHandlerFn(this, function() {
				// серверный commit+apply (без LuCI-стейджинга, иначе остаётся в Unsaved Changes)
				return callSetRouting(taDirect.value, taProxy.value).then(notifyApplied);
			})
		}, [ _('Save & Apply') ]);

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Custom routing (split-tunnel)') ]),
			E('p', { 'style': 'color:#888' }, [ _('One entry per line: domain, *.domain (matches the domain and all subdomains), IP/CIDR, geosite:NAME or geoip:NAME. Active only in split-tunnel modes (not "Everything via VPN").') ]),
			E('div', { 'style': 'display:flex;gap:24px;flex-wrap:wrap' }, [
				E('div', {}, [ E('strong', {}, [ _('Direct (bypass VPN)') ]), taDirect ]),
				E('div', {}, [ E('strong', {}, [ _('Via VPN') ]), taProxy ])
			]),
			E('p', { 'style': 'margin-top:8px' }, [ save ])
		]);
	}
});
