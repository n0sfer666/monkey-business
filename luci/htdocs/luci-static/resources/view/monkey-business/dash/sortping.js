'use strict';
'require baseclass';
'require view.monkey-business.api as api';
'require view.monkey-business.availability as availability';
'require view.monkey-business.model.servers as model';
'require view.monkey-business.kit.sheet as sheet';

return baseclass.extend({
  sort: function () {
    return Promise.all([api.serversOrderGet(), api.serversList()]).then(function (data) {
      var snapshot = data[0],
        rows = {},
        request = Date.now().toString(36) + Math.random().toString(36).slice(2) + 'order';

      if (snapshot.error || data[1].error) return { error: snapshot.error || data[1].error };
      (data[1].servers || []).forEach(function (row) {
        rows[availability.key(row.server_ref)] = row;
      });
      var groups = snapshot.groups.map(function (group) {
        return group
          .map(function (ref, index) {
            return { ref: ref, index: index };
          })
          .sort(function (a, b) {
            var ar = model.rank(model.pingOf(rows[availability.key(a.ref)] || {}));
            var br = model.rank(model.pingOf(rows[availability.key(b.ref)] || {}));

            return ar === br ? a.index - b.index : ar - br;
          })
          .map(function (item) {
            return item.ref;
          });
      });

      return new Promise(function (resolve) {
        var done = false,
          box;
        var message = E('p', {}, [_('Priority applies on the next connection.')]);
        var apply = E(
          'button',
          {
            class: 'mb-btn mb-btn-primary',
            click: function () {
              apply.disabled = true;
              api
                .serversOrderApply(snapshot.revision, request, groups)
                .then(function (result) {
                  if (result.error) {
                    message.textContent = result.error;
                    apply.disabled = false;

                    return;
                  }
                  done = true;
                  box.close();
                  resolve(result);
                })
                .catch(function (error) {
                  message.textContent = error.message;
                  apply.disabled = false;
                });
            },
          },
          [_('Apply priority')],
        );

        box = sheet.open({
          title: _('Review priority'),
          body: [
            message,
            E(
              'ol',
              {},
              [].concat.apply([], groups).map(function (ref) {
                return E('li', {}, [ref.tag]);
              }),
            ),
          ],
          actions: [apply],
          locked: function () {
            return apply.disabled;
          },
          onClose: function () {
            if (!done) resolve({ unchanged: true });
          },
        });
      });
    });
  },
});
