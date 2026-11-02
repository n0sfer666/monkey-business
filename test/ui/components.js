'use strict';
// Actual production components; only LuCI transport and fixture data are replaced.
window._ = function (value) {
  return value;
};
window.E = function (tag, attrs, children) {
  var element = document.createElement(tag);

  Object.entries(attrs || {}).forEach(function (entry) {
    if (typeof entry[1] === 'function') element.addEventListener(entry[0], entry[1]);
    else if (['disabled', 'checked', 'value', 'id'].includes(entry[0])) element[entry[0]] = entry[1];
    else if (entry[1] != null) element.setAttribute(entry[0], entry[1]);
  });
  (children || []).flat().forEach(function (child) {
    element.append(child instanceof Node ? child : document.createTextNode(child == null ? '' : String(child)));
  });

  return element;
};
String.prototype.format = function () {
  var args = Array.from(arguments);

  return this.replace(/%[ds]/g, function () {
    return args.shift();
  });
};
document.body.style.background = 'var(--mb-bg)';
['Light', 'Dark'].forEach(function (theme) {
  document.querySelector('#fixture').append(
    window.E(
      'button',
      {
        click: function () {
          document.documentElement.dataset.darkmode = String(theme === 'Dark');
        },
      },
      [theme],
    ),
  );
});
var candidate = {
  mode: 'global',
  region: 'other',
  direct: '',
  proxy: '',
  corporate_rules: [
    {
      id: 'corp_fixture',
      name: '<script>synthetic literal</script>',
      address: '8.8.8.8',
      port: '443',
      enabled: 1,
      requires_udp: 1,
    },
  ],
};
var snapshot = {
  revision: 'synthetic-revision',
  enabled: true,
  candidate: candidate,
  effective_policy: { corp_fixture: { route: 'direct', reason: 'udp_down' } },
};
var api = {
  routingValidate: async function (value) {
    return {
      valid: value.corporate_rules.every(function (r) {
        return r.name && r.address;
      }),
      items: [{ field: 'address', code: 'public_ipv4_required' }],
    };
  },
  routingApply: async function () {
    return { error: 'synthetic_commit_failure' };
  },
  routingGet: async function () {
    return snapshot;
  },
};
var cache = {
  baseclass: {
    extend: function (value) {
      return value;
    },
  },
  dom: {
    content: function (node, children) {
      node.replaceChildren(...children);
    },
  },
  ui: {
    addNotification: function (_, node) {
      document.body.append(node);
    },
  },
  'view.monkey-business.api': api,
};

async function load(name) {
  if (cache[name]) return cache[name];
  var source = await (await fetch('/luci/htdocs/luci-static/resources/' + name.replaceAll('.', '/') + '.js')).text();
  var matches = Array.from(source.matchAll(/^\s*'require\s+([\w.-]+)(?:\s+as\s+(\w+))?';/gm));
  var args = await Promise.all(
    matches.map(function (m) {
      return load(m[1]);
    }),
  );

  cache[name] = new Function(
    ...matches.map(function (m) {
      return m[2] || m[1];
    }),
    source,
  )(...args);

  return cache[name];
}
(async function () {
  var routing = await load('view.monkey-business.dash.routing');
  var panel = routing.render({ snapshot: snapshot, readonly: false });

  document.querySelector('#fixture').append(panel.node);
  var ping = await load('view.monkey-business.srv.pingbar');

  ['available', 'degraded', 'probe_failed', 'checking', 'unknown', 'config_error', 'cancelled'].forEach(
    function (kind) {
      document
        .querySelector('#fixture')
        .append(
          window.E('p', {}, [
            ping.render({ kind: kind, ms: 187, successes: 1, attempts: 2, udp: { state: 'down' }, age: 67 }),
          ]),
        );
    },
  );
  window.fixturePanel = panel;
  document.documentElement.dataset.ready = 'true';
})().catch(function (error) {
  document.body.append(error.stack);
});
