'use strict';
'require baseclass';
'require dom';
'require view.monkey-business.api as api';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.sheet as sheet';
'require view.monkey-business.kit.icons as icons';
'require view.monkey-business.model.linktext as linktext';
'require view.monkey-business.model.servers as servers';

style.add(
  'serversheet',
  [
    '.mb .mb-lk{gap:5px}',
    '.mb .mb-lk>label span{color:var(--mb-faint)}',
    '.mb .mb-sheet-body textarea.mb-lk-link{height:76px;resize:none;word-break:break-all;font-size:12px}',
    '.mb .mb-lk-say{font-size:12px;color:var(--mb-muted)}',
    '.mb .mb-lk-say.mb-lk-ok{color:var(--mb-ok-text)}',
    '.mb .mb-lk-say.mb-lk-warn{color:var(--mb-warn-text)}',
    '.mb .mb-lk-say.mb-lk-error{color:var(--mb-err-text)}',
    '.mb .mb-lk-chips{display:flex;flex-wrap:wrap;gap:6px}',
    '.mb .mb-lk-chips:empty{display:none}',
    '.mb .mb-lk-chips span{padding:2px 8px;border-radius:4px;font-size:12px;background:var(--mb-btn);color:var(--mb-text-2)}',
    '.mb .mb-lk-del,.mb .mb-lk-del:hover,.mb .mb-lk-mdel,.mb .mb-lk-mdel:hover{background:transparent;color:var(--mb-err-text);border-color:var(--mb-err-edge)!important}',
    '.mb .mb-sheet-foot .mb-lk-del{margin-right:auto;padding:5px 12px}',
    '.mb .mb-lk-del svg{width:14px;height:14px}',
    '.mb .mb-lk-mdel{display:none}',
    style.MOBILE + '{',
    '.mb .mb-lk-sheet .mb-sheet-head{padding:10px 16px 12px}',
    '.mb .mb-lk-sheet .mb-sheet-title{gap:3px}',
    '.mb .mb-lk-sheet .mb-sheet-body{padding:4px 16px 18px}',
    '.mb .mb-lk-sheet .mb-sheet-foot{padding:10px 16px 20px;margin-top:0;border-top:0}',
    '.mb .mb-sheet-body .mb-lk-name{font-size:16px}',
    '.mb .mb-sheet-body textarea.mb-lk-link{height:120px;font-size:15px}',
    '.mb .mb-sheet-foot .mb-lk-del{display:none}',
    '.mb .mb-sheet-body .mb-lk-mdel{display:flex;flex-shrink:0;gap:8px;padding:11px 0}',
    '.mb .mb-lk-mdel svg{width:16px;height:16px}',
    '}',
  ].join(''),
);

var DEBOUNCE_MS = 400;

return baseclass.extend({
  open: function (o) {
    var edit = !!o.sid;
    var seq = 0;
    var timer = null;
    var last = null;
    var parsed = null;
    var done = null;
    var link = E('textarea', {
      id: 'mb-lk-link',
      class: 'mb-input mb-mono mb-lk-link',
      placeholder: 'vless://… ' + _('or') + ' hy2://…',
      autocomplete: 'off',
      spellcheck: 'false',
      'aria-describedby': 'mb-lk-say',
      'data-autofocus': '',
    });
    var say = E('span', { id: 'mb-lk-say', class: 'mb-lk-say', role: 'status' });
    var chips = E('div', { class: 'mb-lk-chips', role: 'group', 'aria-label': _('Recognized from the link') });
    var name = E('input', { id: 'mb-lk-name', type: 'text', class: 'mb-input mb-lk-name', autocomplete: 'off' });
    var cancel = E('button', { type: 'button', class: 'mb-btn' }, [_('Cancel')]);
    var submit = E('button', { type: 'button', class: 'mb-btn mb-btn-primary' }, [edit ? _('Save') : _('Add server')]);
    var s;

    function remover(cls, text) {
      var btn = E('button', { type: 'button', class: 'mb-btn ' + cls, 'aria-haspopup': 'dialog' }, [text]);

      btn.insertAdjacentHTML('afterbegin', icons.TRASH);
      btn.addEventListener('click', function () {
        s.close();
        o.onDelete();
      });

      return btn;
    }

    function show(v, res) {
      parsed = res && res.ok ? res : null;
      say.className = 'mb-lk-say mb-lk-' + v.level;
      say.textContent = v.text;
      link.classList.toggle('mb-bad', v.level === 'error');
      link.setAttribute('aria-invalid', v.level === 'error' ? 'true' : 'false');
      var ep = parsed && servers.endpoint(parsed.server);

      dom.content(
        chips,
        linktext.chips(parsed && parsed.server).map(function (t) {
          return E('span', { class: t === ep ? 'mb-mono' : null }, [t]);
        }),
      );
      name.placeholder = (parsed && parsed.server.tag) || _('Taken from the link');
      submit.disabled = !parsed;
    }

    function answer(value, res) {
      done = { value: value, verdict: linktext.verdict(res), res: res };
      show(done.verdict, res);
    }

    function replay() {
      if (done && done.value === last) show(done.verdict, done.res);
    }

    function check() {
      var value = link.value.trim();

      if (value === last) return;
      last = value;
      var mine = ++seq;

      if (value === '') return answer(value, null);
      api.parseUri(value, o.sid || '').then(
        function (res) {
          if (mine === seq) answer(value, res);
        },
        function (e) {
          if (mine !== seq) return;
          last = null;
          show({ level: 'error', text: _('Check failed: %s').format((e && e.message) || e) }, null);
        },
      );
    }

    function schedule(now) {
      window.clearTimeout(timer);
      if (link.value.trim() === last) return replay();
      if (now) return check();
      parsed = null;
      submit.disabled = true;
      timer = window.setTimeout(check, DEBOUNCE_MS);
    }

    link.addEventListener('input', function () {
      schedule(false);
    });
    link.addEventListener('change', function () {
      schedule(true);
    });
    cancel.addEventListener('click', function () {
      s.close();
    });
    submit.addEventListener('click', function () {
      if (!parsed) return;
      var got = parsed;

      s.close();
      o.onSave(got.server, name.value.trim(), last);
    });

    s = sheet.open({
      title: edit ? _('Edit server') : _('Add server'),
      hint: edit
        ? _('Manual server · paste a new link to replace it')
        : _('A manual server — subscription updates keep it'),
      width: '560px',
      top: '160px',
      mtop: '240px',
      foot: 'row',
      cls: 'mb-lk-sheet',
      back: o.back,
      body: [
        E('div', { class: 'mb-sheet-field mb-lk' }, [
          E('label', { for: 'mb-lk-link' }, [_('Server link')]),
          link,
          say,
          chips,
        ]),
        E('div', { class: 'mb-sheet-field mb-lk' }, [
          E('label', { for: 'mb-lk-name' }, [_('Name'), ' ', E('span', {}, ['· ' + _('optional')])]),
          name,
        ]),
        edit ? remover('mb-lk-mdel', _('Delete server')) : '',
      ],
      actions: edit ? [remover('mb-lk-del', _('Delete')), cancel, submit] : [cancel, submit],
      onClose: function () {
        window.clearTimeout(timer);
        seq++;
      },
    });

    link.value = o.link || '';
    show(o.note ? { level: 'error', text: o.note } : linktext.verdict(null), null);
    if (o.link) check();

    return s;
  },
});
