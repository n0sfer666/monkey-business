'use strict';
'require baseclass';
'require uci';
'require ui';
'require view.monkey-business.api as api';
'require view.monkey-business.model.dirty as dirty';
'require view.monkey-business.model.sidmap as sidmap';
'require view.monkey-business.model.order as order';

var CONF = 'monkey-business';

function ids(list) {
  return list.map(function (s) {
    return s['.name'];
  });
}

function reorder(sids) {
  return uci.callOrder(CONF, sids).then(
    function () {
      uci.unload(CONF);

      return uci.load(CONF);
    },
    function (e) {
      order.chain(sids, function (sid, prev, after) {
        uci.move(CONF, sid, prev, after);
      });
      throw new Error(_('order not saved: ') + ((e && e.message) || e));
    },
  );
}

return baseclass.extend({
  CONF: CONF,

  load: function () {
    return uci.load(CONF);
  },
  get: function (sid, opt) {
    return uci.get(CONF, sid, opt);
  },
  set: function (sid, opt, value) {
    return uci.set(CONF, sid, opt, value);
  },
  add: function (type, name) {
    return uci.add(CONF, type, name);
  },
  remove: function (sid) {
    return uci.remove(CONF, sid);
  },
  move: function (sid1, sid2, after) {
    return uci.move(CONF, sid1, sid2, after);
  },
  sections: function (type, cb) {
    return uci.sections(CONF, type, cb);
  },

  dirty: function () {
    return dirty.pending(uci.state, CONF);
  },
  touched: function (type) {
    return dirty.touched(uci.state, CONF, type);
  },
  pending: function () {
    return api.uciChanges();
  },
  own: function (all) {
    return (all && all[CONF]) || [];
  },
  changes: function () {
    return this.pending().then(this.own);
  },
  orderSaved: function () {
    delete uci.state.reorder[CONF];
  },
  saveFields: function (named) {
    var want = uci.state.reorder[CONF];
    var self = this;

    delete uci.state.reorder[CONF];

    return self.save(named).finally(function () {
      if (want) uci.state.reorder[CONF] = want;
    });
  },
  save: function (named) {
    var made = Object.assign({}, uci.state.creates[CONF]);
    var known = Object.assign({}, uci.state.values[CONF]);
    var want = uci.state.reorder[CONF] ? ids(uci.sections(CONF)) : null;

    delete uci.state.reorder[CONF];

    return uci.save().then(
      function () {
        var names = sidmap.match(
          made,
          uci.sections(CONF).filter(function (s) {
            return !known[s['.name']];
          }),
        );

        if (named) named(names);

        return want ? reorder(sidmap.order(want, names, ids(uci.sections(CONF)))) : null;
      },
      function (e) {
        if (want) uci.state.reorder[CONF] = true;
        throw e;
      },
    );
  },

  reset: function () {
    uci.unload(CONF);
    delete uci.state.reorder[CONF];

    return uci.load(CONF);
  },

  commit: function (all) {
    return Promise.resolve(all || this.pending())
      .then(function (c) {
        return Object.keys(c).some(function (k) {
          return c[k].length;
        })
          ? api.uciApply(false)
          : null;
      })
      .then(function () {
        ui.changes.setIndicator(0);
      });
  },

  apply: function () {
    var self = this;

    return self.save().then(function () {
      return self.commit();
    });
  },
});
