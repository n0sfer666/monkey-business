'use strict';
'require baseclass';
'require form';
'require rpc';

// Поле «вставь ссылку» с живой проверкой. Разбор делает устройство (ubus parse_uri) — своего
// парсера у формы нет намеренно: иначе она принимала бы ссылки, которые роутер поднять не может.

// section — секция, которую правят: сервер не должен оказаться дублем самого себя.
var callParseUri = rpc.declare({
	object: 'monkey-business', method: 'parse_uri', params: [ 'uri', 'section' ]
});

var DEBOUNCE_MS = 400;

// Разбор, который сейчас в полёте. Модалка в LuCI открыта одна за раз, поэтому состояние одно на
// модуль: Save обязан дождаться ответа, иначе сохранит секцию с ещё не заполненными полями.
var pending = null;

function errorText(res) {
	var d = res.detail || '';
	switch (res.error) {
	case 'unparseable':         return _('This is not a valid link');
	case 'multiple_links':      return _('Paste one link — %s found. A list belongs in the subscription field above.').format(d);
	case 'unsupported_scheme':  return _('Protocol %s is not supported').format(d);
	case 'invalid_host':        return _('The address is not valid');
	case 'invalid_port':        return _('The port is not valid');
	case 'missing_uuid':        return _('The link has no UUID');
	case 'invalid_uuid':        return _('The UUID is too long: xray accepts a UUID or any string up to 30 characters');
	case 'missing_password':    return _('The link has no password');
	case 'missing_reality_key': return _('Reality needs a public key (pbk) — this link has none');
	case 'invalid_reality_key': return _('The Reality public key is malformed (expected 43 base64url characters)');
	case 'invalid_short_id':    return _('The Reality short ID must be up to 16 hex characters, even length');
	case 'unsupported_security':return _('Security %s is not supported').format(d);
	case 'unsupported_transport': return _('Transport %s is not supported').format(d);
	case 'flow_needs_tls':      return _('Flow xtls-rprx-vision needs TLS or Reality, not security=none');
	case 'flow_needs_tcp':      return _('Flow xtls-rprx-vision works over TCP only, not %s').format(d);
	case 'unsupported_flow':    return _('Flow %s is not supported').format(d);
	case 'unsupported_obfs':    return _('Obfuscation %s is not supported').format(d);
	case 'missing_obfs_password': return _('Obfuscation salamander needs a password');
	}
	return _('This link cannot be used');
}

function warningText(res) {
	return (res.warnings || []).map(function(w) {
		if (w == 'insecure')
			return _('certificate check is disabled (insecure=1)');
		if (w == 'duplicate')
			return _('this server is already in the list as "%s"').format(res.duplicate || '');
		return w;
	});
}

return baseclass.extend({
	// Промис незавершённой проверки или null.
	pending: function() { return pending; },

	// Отдельно от отрисовки: решение «ок / предупреждение / отказ» тут, DOM — в render().
	verdict: function(res) {
		if (!res || res.error == 'empty')
			return null;
		if (!res.ok)
			return { level: 'error', text: errorText(res) };
		var warn = warningText(res);
		return {
			level: warn.length ? 'warning' : 'ok',
			text: _('Protocol %s is valid').format(res.protocol) +
				(warn.length ? ' — ' + warn.join('; ') : '')
		};
	},

	render: function(verdict) {
		if (verdict == null)
			return E('span', {});
		var color = { ok: '#33a02c', warning: '#d9a406', error: '#e31a1c' }[verdict.level];
		return E('p', { 'style': 'color:' + color + ';margin:.4em 0 0 0' }, [ verdict.text ]);
	},

	// onParsed(modalSection, section_id, flatServer) вызывается только на валидной ссылке —
	// раскладку по опциям знает вызывающий (serverfields), тут только транспорт результата.
	create: function(s, onParsed) {
		var self = this;
		var o = s.option(form.TextValue, '_uri', _('Server link'),
			_('vless:// or hy2:// — the fields below are filled in from it.'));
		o.modalonly = true;
		o.rows = 3;
		o.depends('_mode', 'link');
		o.placeholder = 'hy2://password@host:443/?sni=example.com#name';
		// Виртуальное поле: ссылка нужна только для импорта, в конфиг сервера она не входит.
		o.cfgvalue = function() { return ''; };
		o.write = function() {};
		o.remove = function() {};

		o.renderWidget = function(section_id, option_index, cfgvalue) {
			// this — клон опции в модалке (form.js, cloneOptions), только у него живая section.
			var clone = this;
			var node = form.TextValue.prototype.renderWidget.apply(this, arguments);
			var out = E('div', {});
			var timer = null, seq = 0, last = null;
			var say = function(verdict) {
				out.innerHTML = '';
				out.appendChild(self.render(verdict));
			};
			// Модалку закрывают вместе с полем: узел выпадает из документа, а отложенный разбор — нет.
			// Ответ на него пришёл бы в уже отсоединённые виджеты, а при следующем открытии модалки
			// раскладывал бы прошлую ссылку по новой секции.
			var gone = function() { return !node.isConnected; };
			var check = function(value) {
				value = value.trim();
				// Тот же текст второй раз не разбираем: иначе правка полей после вставки ссылки
				// затиралась бы ответом на неё же. Сравниваем обрезанное, чтобы лишний пробел в
				// конце не считался новой ссылкой.
				if (value === last)
					return;
				last = value;
				if (value == '') {
					out.innerHTML = '';
					return;
				}
				// Ответы приходят в произвольном порядке — устаревший не должен перебить свежий.
				var mine = ++seq;
				var p = callParseUri(value, section_id).then(function(res) {
					if (mine != seq || gone())
						return;
					say(self.verdict(res));
					if (res && res.ok)
						onParsed(clone.section, section_id, res.server);
				}).catch(function(e) {
					// Сорванная проверка не должна запирать текст навсегда: без сброса повторить её
					// можно было бы только изменив ссылку, а поля так и остались бы пустыми.
					last = null;
					if (mine != seq || gone())
						return;
					say({ level: 'error', text: _('Check failed: %s').format(e.message || e) });
				});
				var done = function() { if (pending === p) pending = null; };
				pending = p;
				p.then(done, done);
			};
			var schedule = function(value, now) {
				if (timer != null)
					window.clearTimeout(timer);
				timer = null;
				if (gone()) {
					// Хвост уже отправленного запроса тоже гасим.
					seq++;
					return;
				}
				if (now)
					check(value);
				else
					timer = window.setTimeout(function() { timer = null; schedule(value, true); }, DEBOUNCE_MS);
			};
			node.addEventListener('input', function(ev) {
				schedule(ev.target.value || '', false);
			});
			// Вставили ссылку и сразу нажали Save — паузы в 400 мс ждать нечего: клик снимает фокус,
			// и разбор надо запустить прямо здесь. Слушаем на фазе перехвата: renderWidget отдаёт
			// обёртку, а не саму textarea, и blur наверх не всплывает.
			[ 'change', 'blur' ].forEach(function(evt) {
				node.addEventListener(evt, function(ev) {
					schedule(ev.target.value || '', true);
				}, true);
			});
			return E('div', {}, [ node, out ]);
		};
		return o;
	}
});
