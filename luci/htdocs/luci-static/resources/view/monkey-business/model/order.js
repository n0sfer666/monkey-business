'use strict';
'require baseclass';

function sorted(ids, rankOf) {
  return ids
    .map(function (id, i) {
      return { id: id, i: i, r: rankOf(id) };
    })
    .sort(function (a, b) {
      if (a.r !== b.r) return a.r < b.r ? -1 : 1;

      return a.i - b.i;
    })
    .map(function (e) {
      return e.id;
    });
}

function chain(ids, move) {
  for (var i = 1; i < ids.length; i++) move(ids[i], ids[i - 1], true);
}

function place(ids, sid, target) {
  var from = ids.indexOf(sid);
  var to = ids.indexOf(target);

  if (from < 0 || to < 0 || from === to) return null;
  var out = ids.slice();

  out.splice(from, 1);
  out.splice(to, 0, sid);

  return { ids: out, after: from < to };
}

function neighbour(ids, sid, dir) {
  var at = ids.indexOf(sid) + dir;

  return ids.indexOf(sid) < 0 || at < 0 || at >= ids.length ? null : ids[at];
}

return baseclass.extend({
  sorted: sorted,
  chain: chain,
  place: place,
  neighbour: neighbour,
});
