'use strict';
'require baseclass';
'require view.monkey-business.api as api';
'require ui';
'require view.monkey-business.subs as subs';
'require view.monkey-business.icons as icons';

function reasonText(reason) {
	if (reason === 'exhausted')
		return _('ran out of traffic');
	if (reason === 'expired')
		return _('expired');
	return reason;
}

function optionLabel(sub) {
	return sub.alive ? sub.name : sub.name + ' — ' + _('expired or out of traffic');
}

function reserveText(st) {
	return st.reserve ? _('now via reserve: ') + subs.name(st.subscriptions, st.sub) : '';
}

function bannerText(st) {
	var a = st.autoswitch;
	if (!a)
		return '';
	return _('Switched automatically: %s %s.').format(subs.name(st.subscriptions, a.from), reasonText(a.reason));
}

function switchTo(selectEl, revertTo) {
	ui.showModal(_('Switching subscription…'), [ E('p', { 'class': 'spinning' }, [ _('Selecting a server and applying') ]) ]);
	return api.subscriptionSelect(selectEl.value).then(function(res) {
		ui.hideModal();
		if (!(res && res.error))
			return window.location.reload();
		selectEl.value = revertTo;
		ui.addNotification(null, E('p', {}, [ _('Subscription not switched: ') + res.error ]), 'warning');
	}).catch(function(e) {
		ui.hideModal();
		selectEl.blur();
		ui.addNotification(null, E('p', {}, [ _('No answer yet, the switch may still be applying; the status refreshes on its own: ') + e ]), 'warning');
	});
}

function idsOf(list) {
	return list.map(function(sub) { return sub.id; }).join(' ');
}

function fillOptions(selectEl, list) {
	selectEl.textContent = '';
	list.forEach(function(sub) {
		selectEl.appendChild(E('option', { 'value': sub.id }, [ optionLabel(sub) ]));
	});
}

return baseclass.extend({
	render: function(st) {
		var active = st.active_sub;
		var shown = null;
		var selectEl = E('select', { 'class': 'cbi-input-select', 'style': 'width:auto' }, []);
		selectEl.addEventListener('change', function() { switchTo(selectEl, active); });

		var reserveEl = E('span', { 'style': 'color:#ff7f00' }, []);
		var bannerEl = E('div', {
			'style': 'margin:8px 0;padding:8px 12px;border-left:4px solid #ff7f00;background:rgba(255,127,0,.08)'
		}, [ E('span', { 'style': 'color:#ff7f00' }, [ icons.icon('alert') ]), ' ', E('strong', {}, []) ]);

		var rowEl = E('p', {}, [ _('Subscription: '), selectEl, ' ', reserveEl ]);

		function update(cur) {
			var list = cur.subscriptions || [];
			var focused = document.activeElement === selectEl;
			active = cur.active_sub;
			if (!focused && idsOf(list) !== shown) {
				fillOptions(selectEl, list);
				shown = idsOf(list);
			}
			if (!focused)
				selectEl.value = active;
			Array.prototype.forEach.call(selectEl.options, function(opt) {
				var sub = subs.find(list, opt.value);
				if (sub)
					opt.textContent = optionLabel(sub);
			});
			rowEl.style.display = (list.length > 1) ? '' : 'none';
			reserveEl.textContent = reserveText(cur);
			bannerEl.style.display = cur.autoswitch ? 'block' : 'none';
			bannerEl.lastChild.textContent = bannerText(cur);
		}
		update(st);

		return { banner: bannerEl, row: rowEl, update: update };
	}
});
