'use strict';
'require baseclass';
'require dom';
'require rpc';
'require ui';
'require uci';

// Управление сплитом живёт на дашборде, а не в форме Settings: режим и регион меняют не только
// конфиг xray, но и файрвол (ядерный обход в nft), а форма LuCI умеет лишь стейджить UCI —
// «сохранил, и ничего не произошло» здесь стоило бы дороже всего. Поэтому свой ubus-вызов
// (set_mode), который коммитит и применяет сразу.
var callSetMode = rpc.declare({ object: 'monkey-business', method: 'set_mode', params: ['mode', 'region'] });

var MODES = [
	[ 'bypass-local', _('Bypass local — region and private direct, the rest via VPN') ],
	[ 'gfwlist', _('Only blocked via VPN — everything else direct') ],
	[ 'global', _('Everything via VPN') ]
];

var REGIONS = [
	[ 'ru', _('Russia') ],
	[ 'cn', _('China') ],
	[ 'ir', _('Iran') ],
	[ 'other', _('Other — no geo preset') ]
];

// Имена geosite-категорий не совпадают с кодом региона (см. GEOSITE_REGION в src/generator/xray.uc):
// показывать «geosite:ru» значило бы называть несуществующую категорию.
var GEOSITE = { ru: 'category-ru', cn: 'cn', ir: 'category-ir' };

// Те же правила, что у генератора конфига (buildRouting/buildDns) и init-скрипта
// (mb_direct_bypass): список не «советует», а показывает, что РЕАЛЬНО включится выбранной парой.
// До этого режим и регион были двумя строчками в форме, и по ним нельзя было понять, работает ли
// geoip:<region> вообще, — вне bypass-local такого правила в конфиге нет вовсе.
function effects(mode, region) {
	var geo = (mode == 'bypass-local') && (region != 'other');
	var site = GEOSITE[region] || region;
	var bypass = geo && region == 'ru';
	return [
		[ geo, _('geoip:%s and geosite:%s go direct').format(region, site) ],
		[ bypass, _('kernel bypass: RU subnets skip Xray entirely (nft mb_ru4/mb_ru6)') ],
		[ (mode == 'gfwlist') && (region != 'other'), _('only geosite:geolocation-!%s is sent through the VPN').format(region) ],
		[ mode == 'global', _('every destination goes through the VPN') ],
		[ mode != 'global', bypass
			? _('the custom Direct / Via-VPN lists below are in effect — except for RU addresses, which the kernel bypass takes away from Xray entirely')
			: _('the custom Direct / Via-VPN lists below are in effect') ],
		[ region != 'other', _('DNS: %s domains are resolved directly, the rest over DoH').format(region) ]
	];
}

// Значение из UCI, которого нет в списке (правка руками, конфиг из будущей версии), добавляется
// отдельным пунктом: иначе select остался бы пустым, ушёл бы в set_mode как '' — то есть «не
// трогать» — и панель отрапортовала бы «applied» при нулевом эффекте.
function selectEl(opts, value) {
	var known = opts.filter(function(o) { return o[0] == value; }).length > 0;
	var items = known ? opts : opts.concat([ [ value, value + _(' (unknown)') ] ]);
	var el = E('select', { 'class': 'cbi-input-select' }, items.map(function(o) {
		return E('option', { 'value': o[0] }, [ o[1] ]);
	}));
	el.value = value;
	return el;
}

function field(label, el) {
	return E('div', { 'style': 'display:flex;flex-direction:column;gap:4px' }, [
		E('label', {}, [ label ]), el
	]);
}

return baseclass.extend({
	render: function() {
		var modeEl = selectEl(MODES, uci.get('monkey-business', 'global', 'routing_mode') || 'bypass-local');
		var regionEl = selectEl(REGIONS, uci.get('monkey-business', 'global', 'local_region') || 'ru');
		var listEl = E('ul', { 'style': 'margin:6px 0 0 0;padding-left:18px' }, []);

		function refresh() {
			dom.content(listEl, effects(modeEl.value, regionEl.value).map(function(e) {
				return E('li', { 'style': 'color:' + (e[0] ? '#33a02c' : '#888') },
					[ (e[0] ? '✓ ' : '✗ ') + e[1] ]);
			}));
		}
		modeEl.addEventListener('change', refresh);
		regionEl.addEventListener('change', refresh);
		refresh();

		var save = E('button', {
			'class': 'btn cbi-button cbi-button-apply',
			'click': ui.createHandlerFn(this, function() {
				return callSetMode(modeEl.value, regionEl.value).then(function(res) {
					if (res && res.error)
						ui.addNotification(null, E('p', _('Apply failed: ') + res.error), 'warning');
					else if (res && res.skipped == 'disabled')
						ui.addNotification(null, E('p', _('Saved. The VPN is off — the split applies when you turn it on.')), 'info');
					else
						ui.addNotification(null, E('p', _('Routing mode applied.')), 'info');
				}).catch(function(e) {
					ui.addNotification(null, E('p', _('Apply failed: ') + e), 'error');
				});
			})
		}, [ _('Save & Apply') ]);

		return E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, [ _('Split (what goes through the VPN)') ]),
			E('div', { 'style': 'display:flex;gap:24px;flex-wrap:wrap' }, [
				field(_('Routing mode'), modeEl),
				field(_('Local region'), regionEl)
			]),
			E('p', { 'style': 'margin-top:10px;margin-bottom:0' }, [ E('strong', {}, [ _('With this selection:') ]) ]),
			listEl,
			E('p', { 'style': 'margin-top:10px' }, [ save ]),
			E('p', { 'style': 'color:#888;margin:0' }, [
				_('Private networks always stay direct. Changing this restarts the firewall and reloads Xray.')
			])
		]);
	}
});
