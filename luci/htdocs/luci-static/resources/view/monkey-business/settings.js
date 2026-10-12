'use strict';
'require view';
'require dom';
'require ui';
'require view.monkey-business.api as api';
'require view.monkey-business.store as store';
'require view.monkey-business.kit.style as style';
'require view.monkey-business.kit.tabs as tabs';
'require view.monkey-business.kit.viewbar as viewbar';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.set.sections as sections';

style.add('set-view', style.MOBILE + '{.mb.mb-set .mb-vbar-acts .mb-btn-primary{padding-left:0;padding-right:0}}');

function report(res) {
  if (res && res.error) return notice.show(_('Apply failed: ') + res.error, 'warning');
  if (res && res.skipped === 'disabled')
    return notice.show(_('Saved. The VPN is off — settings will apply when you turn it on.'), 'info');
  notice.show(_('Configuration applied.'), 'info');
}

return view.extend({
  handleSave: null,
  handleSaveApply: null,
  handleReset: null,

  load: function () {
    return store.load();
  },

  render: function () {
    this.root = E('div', { class: 'mb mb-view mb-set' });
    this.draw();

    return this.root;
  },

  draw: function () {
    var self = this;
    var errors = {};
    var readonly = !L.hasViewPermission();
    var locked = readonly;

    function act(name) {
      return ui.createHandlerFn(self, function () {
        locked = true;
        sync();

        return self[name]();
      });
    }

    var reset = E('button', { class: 'mb-btn', click: act('doReset') }, [_('Reset')]);
    var save = E('button', { class: 'mb-btn', click: act('doSave') }, [_('Save')]);
    var apply = E('button', { class: 'mb-btn mb-btn-primary', click: act('doApply') }, [_('Save & Apply')]);

    function sync() {
      var bad = locked || Object.keys(errors).length > 0;
      var dirty = store.dirty();

      reset.disabled = locked || !dirty;
      save.disabled = bad || !dirty;
      apply.disabled = bad;
    }

    dom.content(this.root, [
      tabs.render('settings'),
      viewbar.render(_('Settings'), _('Defaults are safe'), [reset, save, apply]),
      sections.render(errors, sync, readonly),
    ]);
    sync();
  },

  doReset: function () {
    return store
      .reset()
      .then(this.draw.bind(this))
      .catch(function () {
        window.location.reload();
      });
  },

  doSave: function () {
    return store
      .save()
      .catch(function (e) {
        notice.show(_('Save failed: ') + e, 'error');
      })
      .then(this.draw.bind(this));
  },

  doApply: function () {
    return store
      .apply()
      .then(function () {
        return api.configApply();
      })
      .then(report)
      .catch(function (e) {
        notice.show(_('Apply failed: ') + e, 'error');
      })
      .then(this.draw.bind(this));
  },
});
