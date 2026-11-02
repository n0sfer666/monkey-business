'use strict';
'require baseclass';

var GB = 1073741824;

function gb(bytes) {
  var n = parseFloat(bytes);

  return isNaN(n) || n <= 0 ? 0 : n / GB;
}

function date(epoch) {
  var n = parseInt(epoch, 10);

  return isNaN(n) || n <= 0 ? '' : new Date(n * 1000).toISOString().slice(0, 10);
}

function of(st) {
  var t = (st && st.traffic) || {};
  var used = gb(t.used_download) + gb(t.used_upload);
  var total = gb(t.total);
  var expire = date(t.expire);

  if (total > 0)
    return {
      kind: 'limited',
      used: used.toFixed(1),
      total: total.toFixed(1),
      expire: expire,
      pct: Math.min(100, Math.round((used / total) * 100)),
    };
  if (used > 0 || expire) return { kind: 'unlimited', used: used.toFixed(1), expire: expire };

  return { kind: 'none' };
}

return baseclass.extend({
  of: of,
});
