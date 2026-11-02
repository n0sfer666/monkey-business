'use strict';
'require baseclass';
'require view.monkey-business.api as api';
'require view.monkey-business.kit.sheet as sheet';

function ref(server) {
  if (server.server_ref) return server.server_ref;

  return server.source === 'subscription'
    ? { source: 'subscription', sub: server.sub, tag: server.tag }
    : { source: 'manual', tag: server.tag };
}
function key(value) {
  return JSON.stringify([value.source, value.sub || null, value.tag]);
}
function id(value) {
  return value.source === 'subscription' ? value.sub + '/' + value.tag : value.tag;
}
function delay() {
  return new Promise(function (resolve) {
    window.setTimeout(resolve, 750);
  });
}
function run(scope, sub, serverRef) {
  return api.availabilityStart(scope, sub || '', serverRef || {}).then(function (started) {
    if (!started || started.error) return started || { error: 'invalid_response' };
    if (started.api_version !== 2) return { error: _('Reload the page to update the API.') };
    var progress = E('p', { role: 'status', 'aria-live': 'polite' });
    var cancel = E(
      'button',
      {
        class: 'mb-btn',
        click: function () {
          cancel.disabled = true;
          api
            .availabilityCancel(started.job_id)
            .then(function (r) {
              if (r.error) {
                progress.textContent = r.error;
                cancel.disabled = false;
              }
            })
            .catch(function () {
              cancel.disabled = false;
            });
        },
      },
      [_('Cancel check')],
    );
    var box = sheet.open({ title: _('VPN availability'), body: progress, actions: [cancel] });

    function poll() {
      return api.availabilityStatus(started.job_id, 0, 50).then(function (status) {
        if (!status || status.error) return status || { error: 'invalid_response' };
        progress.textContent = _('Completed: %d / %d').format(status.completed, status.total) + ' · ' + status.state;
        if (['completed', 'cancelled', 'incomplete', 'failed'].indexOf(status.state) < 0) return delay().then(poll);
        var rows = status.rows || [],
          pages = Promise.resolve();

        for (var offset = 50; offset < status.total; offset += 50) {
          (function (at) {
            pages = pages.then(function () {
              return api.availabilityStatus(started.job_id, at, 50).then(function (page) {
                if (page.error) throw new Error(page.error);
                rows = rows.concat(page.rows || []);
              });
            });
          })(offset);
        }

        return pages.then(function () {
          return {
            api_version: 2,
            state: status.state,
            reason: status.reason,
            results: rows
              .filter(function (row) {
                return row.complete;
              })
              .map(function (row) {
                return Object.assign({}, row, {
                  id: id(row.server_ref),
                  availability: Object.assign({}, row, { fresh: !!row.fresh }),
                });
              }),
          };
        });
      });
    }

    return poll().finally(function () {
      if (box && box.close) box.close();
    });
  });
}
function one(idOrServer) {
  if (typeof idOrServer === 'object') return run('server', '', ref(idOrServer));

  return api.serversList().then(function (list) {
    var found = (list.servers || []).filter(function (server) {
      return server.id === idOrServer;
    });

    return found.length === 1 ? run('server', '', found[0].server_ref) : { error: 'identity_conflict' };
  });
}

return baseclass.extend({ run: run, one: one, ref: ref, key: key });
