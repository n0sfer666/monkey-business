'use strict';
'require baseclass';
'require view.monkey-business.subs as subs';

var ON = ['1', 'true', 'yes', 'on'];

function isOff(s) {
  return ON.indexOf(String(s.disabled)) >= 0;
}

function isManual(s) {
  return subs.serverSub(s) == null;
}

function endpoint(s) {
  var host = String(s.address || '');

  return (host.indexOf(':') >= 0 ? '[' + host + ']' : host) + ':' + (s.port || '');
}

function title(s) {
  return s.tag || endpoint(s);
}

function protocol(s) {
  if (s.protocol === 'hysteria2') return 'hysteria2';
  if (!s.security) return 'vless';

  return 'vless / ' + (s.security === 'none' ? _('no TLS') : s.security);
}

function visible(servers, subIds) {
  return servers.filter(function (s) {
    var id = subs.serverSub(s);

    return id == null || subIds.length === 0 || subIds.indexOf(id) >= 0;
  });
}

function filtered(servers, by) {
  if (by === 'all') return servers;

  return servers.filter(function (s) {
    return by === 'manual' ? isManual(s) : subs.serverSub(s) === by;
  });
}

function filters(servers, subList) {
  var out = [{ value: 'all', label: _('All') }];

  subList.forEach(function (sub) {
    if (filtered(servers, sub.id).length) out.push({ value: sub.id, label: sub.name });
  });
  if (servers.some(isManual)) out.push({ value: 'manual', label: _('Manual') });

  return out;
}

function pingOf(r) {
  var value = r.availability || r;

  return {
    ms: value.latency_ms == null ? null : value.latency_ms,
    state: value.state || 'unknown',
    fresh: !!value.fresh,
    successes: value.successes || 0,
    attempts: value.attempts || 0,
    udp: value.udp,
    age: value.age,
  };
}

function ping(p) {
  if (p == null) return { kind: 'unknown', state: 'unknown' };

  return Object.assign({}, p, { kind: p.fresh ? p.state : 'unknown' });
}

function byId(servers, id) {
  var found = servers.filter(function (server) {
    return server.id === id;
  });

  return found.length === 1 ? found[0] : null;
}

function rank(p) {
  var classes = { available: 0, degraded: 1, probe_failed: 2 };

  return p && p.fresh && classes[p.state] != null
    ? classes[p.state] * 100000000 + (2 - p.successes) * 1000000 + (p.ms || 0)
    : Infinity;
}

return baseclass.extend({
  isOff: isOff,
  isManual: isManual,
  endpoint: endpoint,
  title: title,
  protocol: protocol,
  visible: visible,
  filtered: filtered,
  filters: filters,
  pingOf: pingOf,
  ping: ping,
  rank: rank,
  byId: byId,
});
