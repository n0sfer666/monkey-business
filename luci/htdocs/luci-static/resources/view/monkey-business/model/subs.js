'use strict';
'require baseclass';
'require view.monkey-business.subs as subs';

var GB = 1073741824;
var DOTS = '••••••';

function idOf(s) {
  return s['.name'];
}

function activeId(sections, want) {
  var ids = sections.map(idOf);

  if (want && ids.indexOf(want) >= 0) return want;

  return ids.length ? ids[0] : null;
}

function title(s) {
  return s.name || idOf(s);
}

function defaultName(count) {
  return _('Subscription %d').format(count + 1);
}

function maskUrl(url) {
  var m = /^([a-z][a-z0-9+.-]*:\/\/)/i.exec(url || '');

  return (m ? m[1] : '') + DOTS + '/' + DOTS;
}

function urlError(url) {
  var v = (url || '').trim();

  if (v === '') return _('URL is required');
  if (!/^https?:\/\/[^\s]+$/i.test(v)) return _('Must start with http:// or https://');

  return null;
}

function gb(bytes) {
  var n = parseFloat(bytes);

  return isNaN(n) || n <= 0 ? 0 : n / GB;
}

function day(epoch) {
  var n = parseInt(epoch, 10);

  return isNaN(n) || n <= 0 ? null : new Date(n * 1000).toISOString().slice(0, 10);
}

function traffic(s) {
  var total = gb(s.total);

  if (total <= 0) return null;
  var used = gb(s.used_upload) + gb(s.used_download);

  return {
    used: used.toFixed(1),
    total: total.toFixed(1),
    pct: Math.min(100, Math.round((used / total) * 100)),
    expire: day(s.expire),
  };
}

function serversOf(servers, id) {
  return servers.filter(function (s) {
    return subs.serverSub(s) === id;
  });
}

function vacant(sub, servers) {
  return !!sub && !sub.url && serversOf(servers, idOf(sub)).length === 0;
}

function refetch(changes, ids) {
  var out = [];

  (changes || []).forEach(function (c) {
    if (c[0] === 'set' && c[2] === 'url' && ids.indexOf(c[1]) >= 0 && out.indexOf(c[1]) < 0) out.push(c[1]);
  });

  return out;
}

return baseclass.extend({
  activeId: activeId,
  title: title,
  defaultName: defaultName,
  maskUrl: maskUrl,
  urlError: urlError,
  traffic: traffic,
  serversOf: serversOf,
  vacant: vacant,
  refetch: refetch,
});
