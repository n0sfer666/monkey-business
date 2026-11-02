'use strict';
'require baseclass';

function copy(value) {
  return JSON.parse(JSON.stringify(value));
}

function create(snapshot) {
  var applied = copy(snapshot);
  var candidate = copy(snapshot.candidate);
  var request = null;

  function dirty() {
    return JSON.stringify(candidate) !== JSON.stringify(applied.candidate);
  }

  return {
    candidate: function () {
      return copy(candidate);
    },
    replace: function (next) {
      candidate = copy(next);
      request = null;
    },
    dirty: dirty,
    revision: function () {
      return applied.revision;
    },
    observe: function (next) {
      if (dirty()) return;
      candidate = copy(next.candidate);
      applied = copy(next);
    },
    payload: function (id) {
      if (!request) request = { expected_revision: applied.revision, request_id: id, candidate: copy(candidate) };

      return copy(request);
    },
    accept: function (next) {
      applied = copy(next);
      candidate = copy(next.candidate);
      request = null;
    },
  };
}

return baseclass.extend({ create: create });
