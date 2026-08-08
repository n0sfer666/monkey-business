'use strict';
'require baseclass';
'require form';
'require uci';
'require view.monkey-business.serveropt as so';

// Набор полей сервера: что именно показывать, зависит от протокола. Как поле ложится в UCI и как
// читается прежняя схема — в serveropt.js. Значение по умолчанию задаёт первый пункт списка, а не
// свойство default: см. комментарий там же.

// Ссылку без этих полей устройство отвергает (missing_uuid/missing_password/missing_obfs_password
// в serverlink.js), значит и ручной ввод обязан спотыкаться на них же. Иначе секция спокойно уезжает
// в UCI, генератор собирает конфиг с пустым паролем/UUID, туннель не поднимается — и снаружи это
// выглядит как «watchdog зачем-то крутит failover», а не как незаполненное поле.
//
// Проверка привязана к видимости (so.shown) и к depends самого поля: у скрытого протоколом поля LuCI
// валидацию не запускает вовсе (form.js parse: isActive), поэтому vless-сервер не спотыкается о
// пустой hysteria-пароль.
function requireFilled(o, msg) {
	o.validate = function(sid, value) {
		if (!so.shown(this, sid))
			return true;
		return (value != null && value !== '') ? true : msg;
	};
	return o;
}

function vlessFields(s, all) {
	all.uuid = so.depends(so.value(s, form.Value, 'uuid', _('UUID')), [ { protocol: 'vless' } ]);
	requireFilled(all.uuid, _('VLESS needs a UUID'));

	all.flow = so.choices(so.value(s, form.ListValue, 'flow', _('Flow')),
		[ [ '', _('none') ], [ 'xtls-rprx-vision', 'xtls-rprx-vision' ],
		  [ 'xtls-rprx-vision-udp443', 'xtls-rprx-vision-udp443' ] ]);
	so.depends(all.flow, [ { protocol: 'vless' } ]);

	all.security = so.choices(so.value(s, form.ListValue, 'security', _('Security')),
		[ [ 'reality', 'Reality' ], [ 'tls', 'TLS' ], [ 'none', _('None') ] ]);
	so.depends(all.security, [ { protocol: 'vless' } ]);

	all.pbk = so.value(s, form.Value, 'pbk', _('Reality public key'), _('pbk from the link'));
	// Те же правила, что у проверки ссылки (src/parser/validate.uc): xray с обрезанным ключом
	// стартует и молча не соединяется, поэтому ручной ввод обязан спотыкаться там же, где ссылка.
	all.pbk.validate = function(sid, value) {
		if (value == null || value === '')
			return _('Reality needs a public key (pbk)');
		return /^[A-Za-z0-9_-]{43}=?$/.test(value) ? true
			: _('Expected 43 base64url characters');
	};
	all.sid = so.value(s, form.Value, 'sid', _('Reality short ID'), _('sid from the link'));
	all.sid.validate = function(sid, value) {
		if (value == null || value === '')
			return true;
		return /^([0-9a-fA-F]{2}){1,8}$/.test(value) ? true
			: _('Expected up to 16 hex characters, even length');
	};
	all.spx = so.value(s, form.Value, 'spx', _('Reality spiderX'));
	all.spx.placeholder = '/';
	[ all.pbk, all.sid, all.spx ].forEach(function(o) {
		so.depends(o, [ { protocol: 'vless', security: 'reality' } ]);
	});

	all.fingerprint = so.value(s, form.Value, 'fingerprint', _('TLS fingerprint'),
		_('chrome, firefox, safari, …'));
	all.fingerprint.placeholder = 'chrome';
	all.alpn = so.value(s, form.Value, 'alpn', _('ALPN'), _('Comma separated, e.g. h2,http/1.1'));
	so.depends(all.fingerprint, [ { protocol: 'vless' } ]);
	so.depends(all.alpn, [ { protocol: 'vless' } ]);

	all.tr_type = so.choices(so.value(s, form.ListValue, 'tr_type', _('Transport')),
		[ [ 'tcp', 'TCP' ], [ 'ws', 'WebSocket' ], [ 'xhttp', 'XHTTP' ], [ 'grpc', 'gRPC' ],
		  [ 'httpupgrade', 'HTTPUpgrade' ] ]);
	so.depends(all.tr_type, [ { protocol: 'vless' } ]);

	var pathed = [ 'ws', 'xhttp', 'httpupgrade' ].map(function(t) {
		return { protocol: 'vless', tr_type: t };
	});
	all.tr_path = so.depends(so.value(s, form.Value, 'tr_path', _('Path')), pathed);
	all.tr_host = so.depends(so.value(s, form.Value, 'tr_host', _('Host header')), pathed);

	all.tr_mode = so.choices(so.value(s, form.ListValue, 'tr_mode', _('XHTTP mode')),
		[ [ 'auto', 'auto' ], [ 'packet-up', 'packet-up' ], [ 'stream-up', 'stream-up' ],
		  [ 'stream-one', 'stream-one' ] ]);
	so.depends(all.tr_mode, [ { protocol: 'vless', tr_type: 'xhttp' } ]);

	all.tr_service = so.depends(so.value(s, form.Value, 'tr_service', _('gRPC service name')),
		[ { protocol: 'vless', tr_type: 'grpc' } ]);
}

function hysteriaFields(s, all) {
	all.password = so.value(s, form.Value, 'password', _('Password'), _('hysteria2 authentication'));
	all.password.password = true;
	requireFilled(all.password, _('hysteria2 needs a password'));
	all.insecure = so.value(s, form.Flag, 'insecure', _('Skip certificate check'),
		_('insecure=1 in the link: traffic stays encrypted, but the server is not verified.'));
	all.obfs_type = so.choices(so.value(s, form.ListValue, 'obfs_type', _('Obfuscation')),
		[ [ '', _('none') ], [ 'salamander', 'salamander' ] ]);
	all.obfs_password = so.value(s, form.Value, 'obfs_password', _('Obfuscation password'));
	// salamander без пароля обфускации — тот же отказ на стороне устройства, что и без пароля вовсе.
	requireFilled(all.obfs_password, _('salamander needs an obfuscation password'));
	all.pin_sha256 = so.value(s, form.Value, 'pin_sha256', _('Certificate pin (SHA256)'));
	all.mport = so.value(s, form.Value, 'mport', _('Port hopping'), _('Range, e.g. 10000-20000'));

	[ all.password, all.insecure, all.obfs_type, all.pin_sha256, all.mport ].forEach(function(o) {
		so.depends(o, [ { protocol: 'hysteria2' } ]);
	});
	so.depends(all.obfs_password, [ { protocol: 'hysteria2', obfs_type: 'salamander' } ]);
}

// Опция в модалке — КЛОН той, что заведена тут (form.js, cloneOptions): у клона свои map и section,
// а исходная опция к модалке не привязана вовсе. Поэтому соседей ищем через section клона в момент
// вызова, а не по ссылке, захваченной при создании формы.
function sibling(o, sid, name) {
	var peer = o.section.getOption(name);
	return peer ? peer.getUIElement(sid) : null;
}

return baseclass.extend({
	// Переключатель «ссылка / ручной ввод» и скрытый признак «поля уже есть что показывать».
	mode: function(s) {
		var show = so.virtual(s, form.HiddenValue, '_show');
		show.cfgvalue = function(sid) { return so.isExisting(sid) ? '1' : ''; };

		var mode = so.virtual(s, form.ListValue, '_mode', _('Add server'));
		mode.value('link', _('Paste a link'));
		mode.value('manual', _('Enter by hand'));
		mode.widget = 'radio';
		mode.orientation = 'horizontal';
		mode.cfgvalue = function(sid) { return so.isExisting(sid) ? 'manual' : 'link'; };
		mode.renderWidget = function(sid, idx, cfgvalue) {
			var self = this;
			var node = form.ListValue.prototype.renderWidget.apply(this, arguments);
			node.addEventListener('change', function() {
				// Обратно поля не прячем: человек мог их уже заполнить, а скрытое поле форма стирает.
				var el = (self.formvalue(sid) === 'manual') ? sibling(self, sid, '_show') : null;
				if (el != null)
					el.setValue('1');
				self.map.checkDepends();
			});
			return node;
		};
	},

	create: function(s) {
		var all = {};
		all.tag = s.option(form.Value, 'tag', _('Name'));
		all.address = s.option(form.Value, 'address', _('Address'));
		all.port = s.option(form.Value, 'port', _('Port'));
		all.port.datatype = 'port';
		// Секцию без адреса сохранить нельзя: пустой сервер остаётся в списке навсегда (подписка его
		// не трогает — source у него нет), а выбор активного берёт просто первый по порядку.
		// Имя обязательно по той же причине: активный сервер хранится тегом, и безымянный не найдётся
		// — туннель поднят, а дашборд показывает «сервера нет».
		//
		// Но обязательность включается вместе с полями (_show), а не сразу: в режиме ссылки заполнять
		// их ещё нечем, и rmempty=false встречал бы человека тремя красными рамками на пустой форме.
		// Пустую секцию в этот момент удерживает проверка самой ссылки (serverlink.js).
		[ all.tag, all.address, all.port ].forEach(function(o) {
			requireFilled(o, _('Must not be empty'));
		});
		all.protocol = so.choices(s.option(form.ListValue, 'protocol', _('Protocol')),
			[ [ 'vless', 'VLESS' ], [ 'hysteria2', 'hysteria2' ] ]);

		vlessFields(s, all);
		hysteriaFields(s, all);

		all.sni = so.depends(so.value(s, form.Value, 'sni', _('SNI'), _('TLS server name')),
			[ { protocol: 'vless' }, { protocol: 'hysteria2' } ]);
		all.source = so.value(s, form.HiddenValue, 'source');
		// Своего поля у encryption нет (у vless осмысленно правится не руками, а панелью), но из
		// ссылки оно приходит: без опции fill() его бы не донёс, и mlkem-сервер уехал бы в xray с
		// подставленным "none" — то есть молча не соединялся бы.
		all.encryption = so.value(s, form.HiddenValue, 'encryption');

		// Блоки прежней схемы: значения из них уже разобраны в плоские поля, а сама строка должна
		// уйти — при чтении вложенный JSON старше плоских опций и перебил бы правку.
		[ 'transport', 'reality', 'obfs' ].forEach(function(name) {
			var o = so.virtual(s, form.HiddenValue, name);
			o.cfgvalue = function() { return ''; };
			o.remove = function(sid) { uci.unset(so.config, sid, name); };
		});
	},

	// Разобранная ссылка -> виджеты модалки. Пишем только в виджеты: в UCI значения попадут обычным
	// сохранением формы, иначе набор ссылки правил бы конфиг мимо кнопок Save/Dismiss.
	//
	// Виджеты полей, которых в новой ссылке нет, чистим — иначе от прошлой попытки остался бы,
	// например, чужой pbk. В UCI при этом может пережить значение поля, скрытого сменой протокола
	// или security (retain, см. serveropt.js): для генератора оно безвредно, а ключ подключения
	// такие поля не учитывает (src/rpcd/subscription.uc).
	fill: function(section, sid, flat) {
		section.children.forEach(function(o) {
			if (o.option.charAt(0) === '_')
				return;
			var el = o.getUIElement(sid);
			if (el == null)
				return;
			var v = flat[o.option];
			el.setValue((v != null) ? String(v) : '');
		});
		section.map.checkDepends();
	}
});
