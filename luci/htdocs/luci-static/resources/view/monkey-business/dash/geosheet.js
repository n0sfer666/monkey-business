'use strict';
'require baseclass';
'require dom';
'require uci';
'require view.monkey-business.api as api';
'require view.monkey-business.util as util';
'require view.monkey-business.store as store';
'require view.monkey-business.kit.sheet as sheet';
'require view.monkey-business.kit.field as field';
'require view.monkey-business.kit.icons as icons';
'require view.monkey-business.kit.busybtn as busybtn';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.model.geo as model';
'require view.monkey-business.dash.geocss as geocss';
'require view.monkey-business.dash.geoupload as upload';

var POLL_MS = 2000;
var POLL_TRIES = 40;

function poll() {
	var tries = 0;
	function step() {
		return api.geoStatus().then(function(g) {
			if (g.state !== 'updating' || ++tries >= POLL_TRIES)
				return g;
			return util.sleep(POLL_MS).then(step);
		});
	}
	return step();
}

function url(id, which) {
	return E('div', { 'class': 'mb-geo-f' }, [
		E('label', { 'for': id }, [ _('Custom %s URL').format(which) ]),
		E('input', {
			'id': id, 'type': 'url', 'inputmode': 'url', 'class': 'mb-input mb-geo-url',
			'spellcheck': 'false', 'autocomplete': 'off', 'autocapitalize': 'off',
			'placeholder': 'https://…/' + which + '.dat ' + _('(optional)'),
			'value': uci.get(store.CONF, 'geo', which + '_url') || ''
		})
	]);
}

return baseclass.extend({
	open: function(o) {
		var hint = E('span', {});
		var geoip = url('mb-geo-ip', 'geoip');
		var geosite = url('mb-geo-site', 'geosite');
		var busy = false;
		var s;

		function paint(g) {
			var sum = model.summary(g);
			hint.textContent = '';
			if (sum)
				hint.append.apply(hint, field.hint(_('Installed') + ' · ' + sum, sum));
		}

		function refresh() {
			return api.geoStatus().then(function(g) {
				paint(g);
				if (o.onChanged)
					o.onChanged();
			}).catch(function() {});
		}

		function hold(run) {
			busy = true;
			s.node.setAttribute('aria-busy', 'true');
			return Promise.resolve().then(run).finally(function() {
				busy = false;
				s.node.removeAttribute('aria-busy');
			});
		}

		function installed(which, res) {
			if (res && res.ok)
				return notice.show(_('%s.dat installed & validated.').format(which), 'info');
			notice.show(_('Rejected: ') + ((res && (res.detail || res.error)) || ''), 'warning');
		}

		function uploader(which) {
			var btn = E('button', { 'type': 'button', 'class': 'mb-btn mb-geo-btn', 'click': function() { if (!busy) input.click(); } },
				busybtn.content(icons.UPLOAD, which + '.dat'));
			var input = upload.pick(which, function(send) {
				if (busy)
					return;
				btn.setAttribute('aria-busy', 'true');
				btn.setAttribute('aria-disabled', 'true');
				dom.content(btn, busybtn.content(icons.UPLOAD, _('Uploading…')));
				hold(function() {
					return send().then(function() { return api.geoInstall(which); })
						.then(function(res) { installed(which, res); return refresh(); })
						.catch(notice.fail(_('Upload failed: ')));
				}).finally(function() {
					btn.removeAttribute('aria-busy');
					btn.removeAttribute('aria-disabled');
					dom.content(btn, busybtn.content(icons.UPLOAD, which + '.dat'));
				});
			});
			return [ btn, input ];
		}

		function update() {
			if (busy)
				return;
			return hold(function() {
				var ip = geoip.querySelector('input').value.trim();
				var site = geosite.querySelector('input').value.trim();
				return api.geoUpdate(ip, site).then(poll).then(function(g) {
					var r = model.result(g);
					notice.show(r.msg, r.kind);
					paint(g);
					if (r.kind === 'info')
						s.close();
					if (o.onChanged)
						o.onChanged();
				}).catch(notice.fail(_('Geo update failed: ')));
			});
		}

		var cancel = E('button', { 'type': 'button', 'class': 'mb-btn', 'click': function() { if (!busy) s.close(); } }, [ _('Cancel') ]);
		var run = busybtn.render({ cls: 'mb-btn-primary', label: _('Update now'), busy: _('Updating…'), icon: null, run: update });

		paint(o.geo);
		s = sheet.open({
			title: _('Geo databases'),
			hint: hint,
			width: '560px',
			top: '150px',
			foot: 'row',
			cls: 'mb-geo-sheet',
			body: [
				E('span', { 'class': 'mb-geo-lead' }, field.hint(
					_('Leave empty to use the default source. Files are validated with Xray before being installed.'),
					_('Leave empty to use the default source. Validated with Xray before install.'))),
				geoip,
				geosite,
				E('div', { 'class': 'mb-geo-up' }, [
					E('span', {}, field.hint(_('Or upload from disk'), _('Or upload from the phone'))),
					E('div', { 'class': 'mb-geo-btns' }, [].concat(uploader('geoip'), uploader('geosite')))
				])
			],
			actions: [ E('span', { 'class': 'mb-geo-fd' }, [ _('URLs are saved when you update') ]), cancel, run ],
			back: o.back,
			locked: function() { return busy; }
		});
		return s;
	}
});
