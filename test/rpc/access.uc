import { open, popen } from 'fs';
const WORK = getenv('MB_RPC_WORK');
function call(object, method, args, session) {
	let file = open(WORK + '/request.json', 'w', 0o600);
	file.write(sprintf('%J', { jsonrpc: '2.0', id: 1, method: 'call',
		params: [session || '00000000000000000000000000000000', object, method, args || {}] }));
	file.close();
	let pipe = popen('curl --disable -s --max-time 4 --data-binary @' + WORK + '/request.json http://127.0.0.1:18888/ubus');
	let raw = pipe.read('all'), code = pipe.close();
	if (code != 0) die('synthetic RPC HTTP failed');
	let response = json(raw);
	if (response.result != null) return response.result;
	return response.error != null ? [response.error.code] : null;
}
function assert(condition, label) { if (!condition) die(label); }
function login(user) {
	let response = call('session', 'login', { username: user, password: 'synthetic' });
	assert(response != null && response[0] == 0, 'synthetic login failed: ' + (response != null ? response[0] : 'no result'));
	return response[1].ubus_rpc_session;
}
let reader = login('mb-reader'), writer = login('mb-writer');
let public_ = call('monkey-business', 'servers_list', {}, reader);
assert(public_[0] == 0 && length(public_[1].servers) == 1, 'read-only server model unavailable');
assert(public_[1].servers[0].uuid == null && public_[1].servers[0].password == null, 'secret in public server model');
assert(call('uci', 'get', { config: 'monkey-business' }, reader)[0] != 0, 'read-only direct UCI bypass');
assert(call('uci', 'get', { config: 'monkey-business' }, writer)[0] == 0, 'write-role UCI positive control failed');
assert(call('monkey-business', 'routing_get', {}, reader)[0] == 0, 'read-only routing model unavailable');
assert(call('monkey-business', 'routing_apply', {}, reader)[0] != 0, 'read-only mutation accepted');
let write = call('monkey-business', 'routing_apply', {}, writer);
assert(write[0] == 0 && write[1].error == 'invalid_request', 'writer routing dispatch positive control failed');

for (let method in ['availability_start', 'availability_cancel', 'availability_settings_get', 'availability_settings_apply', 'servers_order_apply', 'check_exit'])
	assert(call('monkey-business', method, {}, reader)[0] != 0, 'read-only dispatch allowed ' + method);
for (let method in ['servers_ping', 'server_ping', 'subscription_ping']) {
	let result = call('monkey-business', method, {}, reader);
	assert(result[0] == 0 && result[1].error == 'deprecated', 'legacy ping not deprecated');
}
let settings = call('monkey-business', 'availability_settings_get', {}, writer);
assert(settings[0] == 0 && length(settings[1].targets) == 2, 'writer settings unavailable');
let order = call('monkey-business', 'servers_order_get', {}, reader);
assert(order[0] == 0 && length(order[1].groups) == 1, 'public order unavailable');
let args = { expected_revision: order[1].revision, request_id: 'synthetic-order-123456', groups: order[1].groups };
let applied = call('monkey-business', 'servers_order_apply', args, writer);
assert(applied[0] == 0 && applied[1].ok, 'native scoped order failed');
let again = call('monkey-business', 'servers_order_apply', args, writer);
assert(again[0] == 0 && again[1].revision == applied[1].revision, 'order idempotency failed');
assert(call('uci', 'get', { config: 'monkey-business', section: 'global', option: 'routing_mode' }, writer)[1].value == 'global', 'order changed routing');
let invalid = call('monkey-business', 'availability_start', { scope: 'server', server_ref: { source: 'manual', tag: 'missing' } }, writer);
assert(invalid[0] == 0 && invalid[1].error == 'unknown_server', 'writer job scope positive control');
let page = call('monkey-business', 'availability_status', { job_id: '../../etc/passwd', offset: 0, limit: 50 }, reader);
assert(page[0] == 0 && page[1].error != null, 'unsafe status page accepted');
print('PASS: native rpcd read/write ACL, UCI negative, API v2, scoped order and idempotency\n');
