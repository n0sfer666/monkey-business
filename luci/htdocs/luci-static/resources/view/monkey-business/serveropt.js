'use strict';
'require baseclass';
'require uci';

// Фабрика опций сервера. В UCI поля лежат ПЛОСКО (tr_*, pbk/sid/spx, obfs_*) — раскладку держит
// src/lib/servermap.uc. Прежняя схема писала transport/reality/obfs одной JSON-строкой, поэтому
// cfgvalue умеет достать значение из старого блоба: иначе открытая модалка показала бы пустой
// транспорт, а сохранение записало бы эту пустоту поверх рабочего сервера.
//
// default здесь НЕ ставится: LuCI удаляет опцию, значение которой совпало с default (form.js,
// AbstractValue.parse), то есть security=reality исчезал бы из UCI при каждом сохранении. Значение
// по умолчанию задаёт первый пункт списка (он и попадает в UCI), подсказка к тексту — placeholder.

var CONFIG = 'monkey-business';

var LEGACY = {
	tr_type: [ 'transport', 'type' ], tr_path: [ 'transport', 'path' ],
	tr_host: [ 'transport', 'host' ], tr_mode: [ 'transport', 'mode' ],
	tr_service: [ 'transport', 'serviceName' ],
	pbk: [ 'reality', 'publicKey' ], sid: [ 'reality', 'shortId' ], spx: [ 'reality', 'spiderX' ],
	obfs_type: [ 'obfs', 'type' ], obfs_password: [ 'obfs', 'password' ]
};

function blob(sid, name) {
	var raw = uci.get(CONFIG, sid, name);
	if (raw == null || raw === '' || raw === 'null')
		return null;
	try { return JSON.parse(raw); } catch (e) { return null; }
}

// null = прежней схемы нет, значение берётся как есть. alpn обеих схем лежит в одной и той же
// опции, поэтому формат различает содержимое ("[" в начале), а не отсутствие плоского значения.
function legacyValue(sid, name, raw) {
	if (name === 'alpn') {
		if (raw == null || String(raw).charAt(0) !== '[')
			return null;
		try { return (JSON.parse(String(raw)) || []).join(','); } catch (e) { return ''; }
	}
	if (raw != null)
		return null;
	var m = LEGACY[name];
	var o = m ? blob(sid, m[0]) : null;
	return (o != null && o[m[1]] != null) ? String(o[m[1]]) : null;
}

return baseclass.extend({
	config: CONFIG,

	isExisting: function(sid) {
		return uci.get(CONFIG, sid, 'address') != null;
	},

	// Состояние формы, а не сервера: в UCI такие опции не попадают.
	virtual: function(s, cls, name, title, desc) {
		var o = s.option(cls, name, title, desc);
		o.modalonly = true;
		o.write = function() {};
		o.remove = function() {};
		return o;
	},

	value: function(s, cls, name, title, desc) {
		var o = s.option(cls, name, title, desc);
		o.modalonly = true;
		// Значение может прийти из старого блоба, а не из виджета, поэтому пишем всегда: так первое
		// же сохранение секции переводит её на плоскую раскладку.
		o.forcewrite = true;
		// Поле чужого протокола форма не показывает — и стирать его не должна: иначе открытая
		// модалка hysteria2-сервера вычистила бы у него security, а с ним и ключ дедупликации.
		o.retain = true;
		o.cfgvalue = function(sid) {
			var raw = uci.get(CONFIG, sid, name);
			var v = legacyValue(sid, name, raw);
			return (v != null) ? v : (raw != null ? raw : null);
		};
		return o;
	},

	// Раскрыты ли поля сервера: читаем у соседней опции модалки (это КЛОН — см. комментарий к value()),
	// поэтому ищем через section в момент вызова, а не по ссылке времени сборки формы.
	shown: function(o, sid) {
		var peer = o.section ? o.section.getOption('_show') : null;
		var el = peer ? peer.getUIElement(sid) : null;
		return el != null && el.getValue() === '1';
	},

	// Поля показываются, когда есть что показывать: у существующего сервера сразу, у нового —
	// после того, как ссылка разобрана (или человек сам выбрал ручной ввод).
	// Условие копируется: один и тот же объект передают нескольким опциям (общий список для
	// tr_path/tr_host), а depends кладёт его в свою таблицу — правка на месте меняла бы условие и
	// у соседей.
	depends: function(o, conds) {
		conds.forEach(function(c) { o.depends(Object.assign({ _show: '1' }, c)); });
		return o;
	},

	// Парсер подписки намеренно мягкий: панель присылает transport или flow, которых нет в списке
	// (splithttp, quic, свой режим), и такой сервер работает — генератор кладёт значение в конфиг как
	// есть. Select показать его не может, а parse() записал бы первый пункт: открыл модалку, нажал
	// Save — и рабочий сервер молча стал TCP. Поэтому чужое значение добавляется пунктом на лету.
	// Списки копируются: у клона в модалке они общие с исходной опцией (cloneOptions копирует
	// ссылку), и правка на месте копила бы чужие пункты от сервера к серверу.
	choices: function(o, values) {
		values.forEach(function(v) { o.value(v[0], v[1]); });
		var render = o.renderWidget;
		o.renderWidget = function(sid, idx, cfgvalue) {
			var cur = (cfgvalue != null) ? String(cfgvalue) : '';
			if (cur !== '' && this.keylist.indexOf(cur) < 0) {
				this.keylist = this.keylist.slice();
				this.vallist = this.vallist.slice();
				this.value(cur, cur + ' ' + _('(from the subscription)'));
			}
			return render.apply(this, arguments);
		};
		return o;
	}
});
