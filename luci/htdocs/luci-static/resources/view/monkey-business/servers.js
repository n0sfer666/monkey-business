'use strict';
'require view';
'require view.monkey-business.api as api';
'require view.monkey-business.model.requestid as requestid';
'require view.monkey-business.srv.readonly as readonlyView';
'require view.monkey-business.store as store';
'require view.monkey-business.kit.tabs as tabs';
'require view.monkey-business.kit.viewbar as viewbar';
'require view.monkey-business.kit.notify as notice';
'require view.monkey-business.kit.gesture as gesture';
'require view.monkey-business.availability as availability';
'require view.monkey-business.srv.subpanel as subpanel';
'require view.monkey-business.srv.serverpanel as serverpanel';

return view.extend({
  handleSave: null,
  handleSaveApply: null,
  handleReset: null,

  load: function () {
    return Promise.all([
      L.hasViewPermission() ? store.load() : Promise.resolve(null),
      api.serversOrderGet(),
      api.serversList().catch(function () {
        return null;
      }),
    ]);
  },

  render: function (data) {
    if (!L.hasViewPermission()) return readonlyView.render(data[2]);
    this.orderRevision = data[1].revision;
    var self = this;
    var readonly = !L.hasViewPermission();
    var busy = false;

    function usable(el) {
      return !!(el && el.isConnected && !el.disabled);
    }

    function hold(work, back, spare) {
      busy = true;
      self.sync();

      return Promise.resolve()
        .then(work)
        .finally(function () {
          busy = false;
          self.sync();
          var to = usable(back) ? back : spare && spare();

          if (usable(to)) to.focus();
        });
    }

    function act(name) {
      return function (ev) {
        var back = ev.currentTarget;

        if (busy) return;
        back.classList.add('spinning');

        return hold(
          function () {
            return self[name]();
          },
          back,
          function () {
            return self.apply;
          },
        ).finally(function () {
          back.classList.remove('spinning');
        });
      };
    }

    this.reset = E('button', { class: 'mb-btn', click: act('doReset') }, [_('Reset')]);
    this.save = E('button', { class: 'mb-btn', click: act('doSave') }, [_('Save')]);
    this.apply = E('button', { class: 'mb-btn mb-btn-primary', click: act('doApply') }, [_('Apply priority')]);
    this.sync = function () {
      var locked = readonly || busy;
      var dirty = store.dirty();

      self.root.inert = busy;
      self.reset.disabled = locked || !dirty;
      self.save.disabled = locked || !dirty;
      self.apply.disabled = locked;
    };

    this.servers = serverpanel.create({ list: data[2], readonly: readonly, onChange: this.sync });
    this.subs = subpanel.create({
      onChange: this.sync,
      onRename: function () {
        gesture.after(self.servers.relabel);
        self.sync();
      },
      onRemove: function () {
        self.servers.draw();
        self.sync();
      },
      onFail: function () {
        self.draw();
      },
      onReload: this.renew.bind(this),
      onSaved: this.servers.saved,
      readonly: readonly,
      hold: function (work, spare) {
        return hold(work, null, spare);
      },
      onPing: this.servers.onPing,
    });
    this.root = E('div', { class: 'mb mb-view' }, [
      tabs.render('servers'),
      viewbar.render(_('Servers'), _('Row order is the connect priority'), [this.reset, this.save, this.apply]),
      this.subs.node,
      this.servers.node,
    ]);
    this.sync();
    window.addEventListener('beforeunload', function (event) {
      if (store.dirty()) {
        event.preventDefault();
        event.returnValue = '';
      }
    });
    this.root.querySelectorAll('a[href]').forEach(function (link) {
      link.addEventListener('click', function (event) {
        if (store.dirty() && !window.confirm(_('Discard draft changes and leave?'))) event.preventDefault();
      });
    });

    return this.root;
  },

  draw: function () {
    this.subs.draw();
    this.servers.draw();
    this.sync();
  },

  reload: function () {
    var self = this;

    return store.reset().then(function () {
      self.servers.reset();
      self.draw();
    });
  },

  renew: function () {
    var self = this;

    this.servers.forget();

    return this.reload().then(function () {
      return self.servers.relist();
    });
  },

  doReset: function () {
    return this.reload().catch(function () {
      window.location.reload();
    });
  },

  doSave: function () {
    return store
      .saveFields(this.servers.saved)
      .catch(notice.fail(_('Save failed: ')))
      .then(this.draw.bind(this));
  },

  doApply: function () {
    var self = this;
    var groups = {},
      list = [];

    store.sections('server').forEach(function (server) {
      var ref = availability.ref(server);
      var group = JSON.stringify([ref.source, ref.sub || null]);

      if (!groups[group]) {
        groups[group] = [];
        list.push(groups[group]);
      }
      groups[group].push(ref);
    });
    if (this.orderBody !== JSON.stringify(list)) this.orderRequest = null;
    this.orderBody = JSON.stringify(list);
    if (!this.orderRequest) this.orderRequest = requestid.create();

    return api
      .serversOrderApply(this.orderRevision, this.orderRequest, list)
      .then(function (result) {
        if (result.error) return notice.show(_('Apply failed: ') + result.error, 'warning');
        self.orderRevision = result.revision;
        self.orderRequest = null;
        store.orderSaved();
        self.sync();
        notice.show(_('Priority saved. It applies on the next connection.'), 'info');
      })
      .catch(notice.fail(_('Apply failed: ')));
  },
});
