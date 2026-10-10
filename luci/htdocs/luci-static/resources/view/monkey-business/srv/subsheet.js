'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.sheet as sheet';
'require view.monkey-business.kit.reveal as reveal';
'require view.monkey-business.model.subs as model';

style.add('subsheet', [
	'.mb .mb-sf{display:flex;flex-direction:column;gap:5px;margin-top:12px}',
	'.mb .mb-sf:first-child{margin-top:0}',
	'.mb .mb-sf>label{font-weight:500}',
	'.mb .mb-sf-hint{color:var(--mb-muted);font-size:12px}',
	'.mb .mb-sf-hint.mb-bad{color:var(--mb-err-text)}',
	'.mb .mb-sf-url{display:flex;gap:6px}',
	'.mb .mb-sf-url .mb-icon{flex-shrink:0;width:32px;height:auto}',
	'.mb .mb-sf-fail{margin-top:12px;padding:9px 11px;border-radius:6px;background:var(--mb-err-tint);',
	'border:1px solid var(--mb-err-edge);color:var(--mb-err-text)}',
	'.mb .mb-sf-fail[hidden]{display:none}',
	'.mb .mb-sf-fail p{margin:2px 0 0;color:var(--mb-text-2)}',
	style.MOBILE + '{.mb .mb-sf-url .mb-icon{width:44px}}'
].join(''));

return baseclass.extend({
	open: function(o) {
		var touched = false;
		var busy = false;
		var name = E('input', { 'id': 'mb-sf-name', 'type': 'text', 'class': 'mb-input', 'value': o.name, 'autocomplete': 'off' });
		var url = E('input', {
			'id': 'mb-sf-url', 'type': 'password', 'class': 'mb-input mb-mono', 'placeholder': 'https://…',
			'autocomplete': 'off', 'spellcheck': 'false', 'aria-describedby': 'mb-sf-url-hint', 'data-autofocus': ''
		});
		var hint = E('span', { 'id': 'mb-sf-url-hint', 'class': 'mb-sf-hint' });
		var head = E('strong', {});
		var reason = E('code', {});
		var tail = E('span', {});
		var fail = E('div', { 'class': 'mb-sf-fail', 'role': 'alert', 'hidden': '' }, [ head, E('p', {}, [ reason, tail ]) ]);
		var cancel = E('button', { 'type': 'button', 'class': 'mb-btn' }, [ _('Cancel') ]);
		var add = E('button', { 'type': 'button', 'class': 'mb-btn mb-btn-primary' }, [ _('Add & fetch') ]);
		var s;

		function check() {
			var err = model.urlError(url.value);
			var quiet = !touched && url.value === '';
			hint.textContent = quiet ? _('Paste the VPNON subscription link') :
				(err || _('The server list is fetched from it on save'));
			hint.classList.toggle('mb-bad', !quiet && !!err);
			url.classList.toggle('mb-bad', !quiet && !!err);
			url.setAttribute('aria-invalid', !quiet && err ? 'true' : 'false');
			add.disabled = busy || !!err;
			cancel.disabled = busy;
		}

		function failed(title, text, rest) {
			head.textContent = title;
			reason.textContent = text;
			tail.textContent = rest;
			fail.hidden = false;
		}

		function submit() {
			if (busy || model.urlError(url.value))
				return;
			busy = true;
			fail.hidden = true;
			add.textContent = _('Fetching…');
			check();
			Promise.resolve(o.onAdd(name.value.trim() || o.name, url.value.trim())).then(function(res) {
				if (res && res.error)
					return failed(_('Couldn\'t fetch the subscription'), res.error,
						' — ' + _('nothing was saved. Check the URL and try again.'));
				s.close();
			}, function(e) {
				failed(_('Couldn\'t add the subscription'), String(e && e.message || e), '');
			}).finally(function() {
				busy = false;
				add.textContent = _('Add & fetch');
				check();
			});
		}

		url.addEventListener('input', function() { touched = true; check(); });
		url.addEventListener('blur', function() { touched = true; check(); });
		url.addEventListener('keydown', function(ev) { if (ev.key === 'Enter') submit(); });
		cancel.addEventListener('click', function() { if (!busy) s.close(); });
		add.addEventListener('click', submit);

		s = sheet.open({
			title: _('Add subscription'),
			hint: o.hint,
			width: '480px',
			body: E('div', {}, [
				E('div', { 'class': 'mb-sf' }, [ E('label', { 'for': 'mb-sf-name' }, [ _('Name') ]), name ]),
				E('div', { 'class': 'mb-sf' }, [
					E('label', { 'for': 'mb-sf-url' }, [ _('Subscription URL') ]),
					E('div', { 'class': 'mb-sf-url' }, [ url, reveal.render(url, { show: _('Show URL'), hide: _('Hide URL') }) ]),
					hint
				]),
				fail
			]),
			actions: [ cancel, add ],
			back: o.back,
			locked: function() { return busy; }
		});
		check();
		return s;
	}
});
