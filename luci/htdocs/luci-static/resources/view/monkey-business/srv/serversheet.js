'use strict';
'require baseclass';
'require dom';
'require view.monkey-business.api as api';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.sheet as sheet';
'require view.monkey-business.model.linktext as linktext';

style.add('serversheet', [
	'.mb .mb-lk{display:flex;flex-direction:column;gap:5px;margin-top:12px}',
	'.mb .mb-lk:first-child{margin-top:0}',
	'.mb .mb-lk>label{font-weight:500}',
	'.mb .mb-lk>label span{color:var(--mb-muted);font-weight:400}',
	'.mb textarea.mb-lk-link{height:76px;resize:vertical;word-break:break-all}',
	'.mb .mb-lk-say{font-size:12px;color:var(--mb-muted)}',
	'.mb .mb-lk-say.mb-lk-ok{color:var(--mb-ok-text)}',
	'.mb .mb-lk-say.mb-lk-warn{color:var(--mb-warn-text)}',
	'.mb .mb-lk-say.mb-lk-error{color:var(--mb-err-text)}',
	'.mb .mb-lk-chips{display:flex;flex-wrap:wrap;gap:6px}',
	'.mb .mb-lk-chips:empty{display:none}',
	'.mb .mb-lk-del{margin-right:auto}',
	style.MOBILE + '{.mb .mb-lk-del{margin-right:0}}',
	'.mb .mb-lk-chips span{padding:1px 8px;border-radius:4px;font-size:12px;background:var(--mb-line);color:var(--mb-text-2)}'
].join(''));

var DEBOUNCE_MS = 400;

return baseclass.extend({
	open: function(o) {
		var edit = !!o.sid;
		var seq = 0;
		var timer = null;
		var last = null;
		var parsed = null;
		var done = null;
		var link = E('textarea', {
			'id': 'mb-lk-link', 'class': 'mb-input mb-mono mb-lk-link', 'placeholder': 'vless://… ' + _('or') + ' hy2://…',
			'autocomplete': 'off', 'spellcheck': 'false', 'aria-describedby': 'mb-lk-say', 'data-autofocus': ''
		});
		var say = E('span', { 'id': 'mb-lk-say', 'class': 'mb-lk-say', 'aria-live': 'polite' });
		var chips = E('div', { 'class': 'mb-lk-chips' });
		var name = E('input', { 'id': 'mb-lk-name', 'type': 'text', 'class': 'mb-input', 'autocomplete': 'off' });
		var cancel = E('button', { 'type': 'button', 'class': 'mb-btn' }, [ _('Cancel') ]);
		var submit = E('button', { 'type': 'button', 'class': 'mb-btn mb-btn-primary' }, [ edit ? _('Save') : _('Add') ]);
		var del = E('button', { 'type': 'button', 'class': 'mb-btn mb-btn-danger mb-lk-del' }, [ _('Delete') ]);
		var s;

		function show(v, res) {
			parsed = res && res.ok ? res : null;
			say.className = 'mb-lk-say mb-lk-' + v.level;
			say.textContent = v.text;
			link.classList.toggle('mb-bad', v.level === 'error');
			link.setAttribute('aria-invalid', v.level === 'error' ? 'true' : 'false');
			dom.content(chips, linktext.chips(parsed && parsed.server).map(function(t) { return E('span', {}, [ t ]); }));
			name.placeholder = (parsed && parsed.server.tag) || '';
			submit.disabled = !parsed;
		}

		function answer(value, res) {
			done = { value: value, verdict: linktext.verdict(res), res: res };
			show(done.verdict, res);
		}

		function replay() {
			if (done && done.value === last)
				show(done.verdict, done.res);
		}

		function check() {
			var value = link.value.trim();
			if (value === last)
				return;
			last = value;
			var mine = ++seq;
			if (value === '')
				return answer(value, null);
			api.parseUri(value, o.sid || '').then(function(res) {
				if (mine === seq)
					answer(value, res);
			}, function(e) {
				if (mine !== seq)
					return;
				last = null;
				show({ level: 'error', text: _('Check failed: %s').format(e && e.message || e) }, null);
			});
		}

		function schedule(now) {
			window.clearTimeout(timer);
			if (link.value.trim() === last)
				return replay();
			if (now)
				return check();
			parsed = null;
			submit.disabled = true;
			timer = window.setTimeout(check, DEBOUNCE_MS);
		}

		link.addEventListener('input', function() { schedule(false); });
		link.addEventListener('change', function() { schedule(true); });
		cancel.addEventListener('click', function() { s.close(); });
		submit.addEventListener('click', function() {
			if (!parsed)
				return;
			var got = parsed;
			s.close();
			o.onSave(got.server, name.value.trim(), last);
		});
		del.addEventListener('click', function() {
			s.close();
			o.onDelete();
		});

		s = sheet.open({
			title: edit ? _('Edit server') : _('Add server'),
			hint: edit ? _('Manual server · paste a new link to replace it') : _('A manual server — subscription updates keep it'),
			width: '520px',
			back: o.back,
			body: E('div', {}, [
				E('div', { 'class': 'mb-lk' }, [ E('label', { 'for': 'mb-lk-link' }, [ _('Link') ]), link, say, chips ]),
				E('div', { 'class': 'mb-lk' }, [
					E('label', { 'for': 'mb-lk-name' }, [ _('Name'), ' ', E('span', {}, [ '· ' + _('optional') ]) ]),
					name
				])
			]),
			actions: edit ? [ del, cancel, submit ] : [ cancel, submit ],
			onClose: function() {
				window.clearTimeout(timer);
				seq++;
			}
		});

		link.value = o.link || '';
		show(o.note ? { level: 'error', text: o.note } : linktext.verdict(null), null);
		if (o.link)
			check();
		return s;
	}
});
