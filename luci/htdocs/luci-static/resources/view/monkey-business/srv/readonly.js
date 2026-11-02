'use strict';
'require baseclass';
'require view.monkey-business.kit.tabs as tabs';
'require view.monkey-business.kit.viewbar as viewbar';

return baseclass.extend({
  render: function (list) {
    var servers = (list || {}).servers || [];

    return E('div', { class: 'mb mb-view' }, [
      tabs.render('servers'),
      viewbar.render(_('Servers'), _('Read-only status'), []),
      E(
        'section',
        { class: 'mb-panel' },
        servers.map(function (server) {
          return E('div', { class: 'mb-srow' }, [
            E('strong', {}, [server.tag]),
            E('span', {}, [server.address + ':' + server.port]),
            E('span', {}, [server.protocol]),
            E('span', { class: 'mb-muted' }, [server.disabled ? _('Off') : _('Enabled')]),
          ]);
        }),
      ),
    ]);
  },
});
