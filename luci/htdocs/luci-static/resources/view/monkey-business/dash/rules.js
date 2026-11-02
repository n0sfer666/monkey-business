'use strict';
'require baseclass';
'require dom';
'require view.monkey-business.api as api';
'require view.monkey-business.kit.sheet as sheet';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.model.routing as routing';
'require view.monkey-business.model.rulemsg as msg';
'require view.monkey-business.dash.rulescss as rulescss';
'require view.monkey-business.dash.ruleerrs as ruleerrs';
'require view.monkey-business.dash.rulelists as rulelists';

var DEBOUNCE_MS = 400;

function applied(res) {
  if (res && res.skipped === 'disabled')
    return notice.show(_('Rules saved. The VPN is off — they will apply when you turn it on.'), 'info');
  notice.show(_('Routing rules applied.'), 'info');
}

return baseclass.extend({
  open: function (o) {
    var defs = rulelists.lists();
    var root = E('div', { class: 'mb-cr', 'data-tab': 'proxy' });
    var tabs = E('div', { class: 'mb-cr-tabs', role: 'tablist', 'aria-label': _('Rule lists') });
    var thint = E('span', { class: 'mb-cr-thint' });
    var cols = E('div', { class: 'mb-cr-cols' });
    var errs = ruleerrs.render(defs);
    var fm = E('span', { class: 'mb-cr-fm' });
    var fd = E('span', { class: 'mb-cr-fd' });
    var cancel = E('button', { type: 'button', class: 'mb-btn' }, [_('Cancel')]);
    var save = E('button', { type: 'button', class: 'mb-btn mb-btn-primary', 'aria-describedby': errs.id }, [
      o.onDraft ? _('Done') : _('Save & Apply'),
    ]);
    var items = [];
    var busy = false;
    var seq = 0;
    var timer, s;

    defs.forEach(function (d) {
      cols.appendChild(rulelists.column(d, o[d.key], pick));
      d.ed.textarea.addEventListener('input', changed);
    });
    defs
      .slice()
      .reverse()
      .forEach(function (d) {
        tabs.appendChild(d.tab);
      });

    function cur() {
      return root.getAttribute('data-tab');
    }

    function pick(key, focus) {
      root.setAttribute('data-tab', key);
      defs.forEach(function (d) {
        var on = d.key === key;

        d.tab.setAttribute('aria-selected', on ? 'true' : 'false');
        d.tab.tabIndex = on ? 0 : -1;
        if (on && focus) d.tab.focus();
        if (on) thint.textContent = d.hint;
      });
      paint();
    }

    function paint() {
      var total = items.length;
      var mine = msg.byList(items, cur()).length;

      defs.forEach(function (d) {
        var bad = msg.byList(items, d.key);
        var n = routing.count(d.ed.textarea.value);

        d.ed.mark(bad, errs.id);
        d.count.textContent = bad.length
          ? _('%d entries · %d invalid').format(n, bad.length)
          : _('%d entries').format(n);
        d.tcount.textContent = bad.length ? _('%d invalid').format(bad.length) : String(n);
        d.count.classList.toggle('mb-bad', bad.length > 0);
        d.tcount.classList.toggle('mb-bad', bad.length > 0);
      });
      errs.update(
        items,
        function (i) {
          return defs[i.list === 'direct' ? 0 : 1].ed.textarea.value.split('\n')[i.line - 1];
        },
        mine === 0,
      );
      fd.textContent = total
        ? _('Fix the highlighted lines to save')
        : _('Applies in split modes only, ignored in “Everything via VPN”');
      fm.textContent = msg.mobileFoot(total, total - mine);
      fd.classList.toggle('mb-bad', total > 0);
      fm.classList.toggle('mb-bad', total > 0);
      save.disabled = busy || total > 0;
      cancel.disabled = busy;
    }

    function text(key) {
      return defs[key === 'direct' ? 0 : 1].ed.textarea.value;
    }

    function check() {
      var id = ++seq;

      return api
        .routingCheck(text('direct'), text('proxy'))
        .then(function (res) {
          if (id !== seq || !res || !Array.isArray(res.items)) return;
          items = res.items;
          paint();
        })
        .catch(function () {
          if (id !== seq) return;
          items = [];
          paint();
        });
    }

    function changed() {
      clearTimeout(timer);
      timer = setTimeout(check, DEBOUNCE_MS);
      paint();
    }

    function submit() {
      if (busy || items.length) return;
      if (o.onDraft) {
        o.onDraft({ direct: text('direct'), proxy: text('proxy') });
        s.close();

        return;
      }
      busy = true;
      paint();
      api
        .setRouting(text('direct'), text('proxy'))
        .then(
          function (res) {
            if (res && res.error === 'invalid_rules') {
              items = res.items || [];

              return;
            }
            if (res && res.error) return notice.show(_('Rules not saved: ') + res.error, 'warning');
            applied(res);
            s.close();
          },
          notice.fail(_('Apply failed: ')),
        )
        .finally(function () {
          busy = false;
          paint();
          if (!root.isConnected && o.onSaved) o.onSaved();
        });
    }

    tabs.addEventListener('keydown', function (ev) {
      if (ev.key === 'ArrowLeft' || ev.key === 'ArrowRight') pick(cur() === 'proxy' ? 'direct' : 'proxy', true);
    });
    cancel.addEventListener('click', function () {
      if (!busy) s.close();
    });
    save.addEventListener('click', submit);
    dom.content(root, [tabs, thint, cols, errs.node, fm]);

    s = sheet.open({
      title: _('Custom rules'),
      hint: rulelists.hint(),
      width: '860px',
      top: '96px',
      mtop: '96px',
      foot: 'row',
      cls: 'mb-cr-sheet',
      body: root,
      actions: [fd, cancel, save],
      back: o.back,
      locked: function () {
        return busy;
      },
      onClose: function () {
        clearTimeout(timer);
        seq++;
      },
    });
    pick('proxy');
    check();

    return s;
  },
});
