'use strict';
'require baseclass';
'require rpc';

var SLOW_SECS = 90;

function mb(method, params) {
  return rpc.declare({ object: 'monkey-business', method: method, params: params || [] });
}

function slow(call) {
  return function () {
    var prev = L.env.rpctimeout;

    L.env.rpctimeout = SLOW_SECS;
    try {
      return call.apply(this, arguments);
    } finally {
      L.env.rpctimeout = prev;
    }
  };
}

return baseclass.extend({
  status: mb('status'),
  serviceToggle: slow(mb('service_toggle', ['enabled'])),
  checkExit: mb('check_exit', ['domain']),
  configApply: slow(mb('config_apply')),
  setMode: mb('set_mode', ['mode', 'region']),
  setRouting: mb('set_routing', ['direct', 'proxy']),
  routingGet: mb('routing_get'),
  routingValidate: mb('routing_validate', ['candidate']),
  routingApply: mb('routing_apply', ['expected_revision', 'request_id', 'candidate']),
  routingCheck: mb('routing_check', ['direct', 'proxy']),
  serversList: mb('servers_list'),
  availabilityStart: mb('availability_start', ['scope', 'sub', 'server_ref']),
  availabilityStatus: mb('availability_status', ['job_id', 'offset', 'limit']),
  availabilityCancel: mb('availability_cancel', ['job_id']),
  availabilitySettingsGet: mb('availability_settings_get'),
  availabilitySettingsApply: mb('availability_settings_apply', ['expected_revision', 'targets']),
  serversOrderGet: mb('servers_order_get'),
  serversOrderApply: mb('servers_order_apply', ['expected_revision', 'request_id', 'groups']),
  parseUri: mb('parse_uri', ['uri', 'section']),
  serverLink: mb('server_link', ['section']),
  subscriptionUpdate: slow(mb('subscription_update', ['sub', 'url'])),
  subscriptionAdd: slow(mb('subscription_add', ['name', 'url'])),
  subscriptionSelect: slow(mb('subscription_select', ['sub'])),
  serverConnect: slow(mb('server_connect', ['id', 'server_ref'])),
  geoStatus: mb('geo_status'),
  geoUpdate: mb('geo_update', ['geoip_url', 'geosite_url']),
  geoInstall: mb('geo_install', ['which']),
  hysteriaStatus: mb('hysteria_status'),
  hysteriaInstall: mb('hysteria_install'),
  uciChanges: rpc.declare({ object: 'uci', method: 'changes', expect: { changes: {} }, reject: true }),
  uciApply: rpc.declare({ object: 'uci', method: 'apply', params: ['rollback'], reject: true }),
});
