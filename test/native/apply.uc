// Real procd, Xray, nft and UCI. Only this snapshot VM's synthetic config is used.
import * as uci from 'uci';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
import { readfile, chmod, popen } from 'fs';
import { corporateRuntime } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/corporate.uc';
import { monotonic } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/routing-v2.uc';
import { applyRuntime } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/apply.uc';
import { routingRuntime } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/routing-v2.uc';
import { applyRouting } from '/usr/share/rpcd/ucode/lib/monkey-business/lib/routing-transaction.uc';
import { generateJson } from '/usr/share/rpcd/ucode/lib/monkey-business/generator/xray.uc';
import { loadApplied, storeApplied } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/applied.uc';
import { listenerOwner } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/engine-listener.uc';
import { atomicPrivate, nonce, privateJson, privateDirectory } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
let c = uci.cursor();
c.set('monkey-business', 'global', 'global'); c.set('monkey-business', 'global', 'enabled', '0');
c.set('monkey-business', 'global', 'routing_mode', 'global');
c.set('monkey-business', 'global', 'local_region', 'other');
c.commit('monkey-business');
let config = { server: { tag: 'actually-applied', source: 'manual', protocol: 'vless', address: '10.0.2.2', port: 14080,
 uuid: '11111111-2222-3333-4444-555555555555', encryption: 'none', security: 'none', transport: { type: 'tcp' } },
 global: { enabled: '0', routing_mode: 'global', local_region: 'other', tproxy_port: '12345', lan_iface: 'mb-apply-router', kill_switch: '0', ipv6_block: '0' },
 health: { port: 11800, credentials: { user: nonce(), pass: nonce() } }, corporate_rules: [] };
let app = applyRuntime(sh), error = app.applyConfig(generateJson(config), true, config, null, { json: null });
if (error != null) { print(sh.runCapture('logread | tail -20; ubus call service list \'{"name":"monkey-business"}\'').out); die('real activation failed: ' + error); }
c.set('monkey-business', 'global', 'enabled', '1'); c.commit('monkey-business');
let applied = loadApplied();
if (listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800) == null) die('activation accepted without listener');
print('PASS: real Apply waits for procd/Xray and nft before publishing snapshot\n');
// Committed, unrelated settings must not enter routing-only Apply.
c.set('monkey-business', 'global', 'tproxy_port', '65000');
c.set('monkey-business', 'global', 'kill_switch', '1');
c.set('monkey-business', 'dns', 'dns'); c.set('monkey-business', 'dns', 'direct_dns', '192.0.2.77');
c.commit('monkey-business');
function fresh() { if (!privateDirectory('/tmp/mb-runtime/uci')) die('unsafe test UCI savedir'); return uci.cursor('/etc/config', '/tmp/mb-runtime/uci'); }
let rt = routingRuntime(sh, fresh, app, function() { return listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800) != null; });
let before = rt.routingSnapshot(), candidate = before.candidate;
candidate.mode = 'gfwlist'; candidate.region = 'other';
candidate.corporate_rules = [{ id: 'corp_native', name: 'Synthetic', address: '8.8.8.8', port: '18081', enabled: true, requires_udp: false }];
let result = applyRouting(rt, { expected_revision: before.revision, request_id: nonce(), candidate: candidate });
if (result.error != null) die('real scoped apply failed: ' + sprintf('%J', result));
let next = loadApplied(), nft = sh.runCapture('nft list table inet monkey_business').out;
if (next.generation != applied.generation || next.config.server.uuid != config.server.uuid || next.config.global.tproxy_port != '12345' ||
 next.config.dns != null || next.config.health.credentials.pass != config.health.credentials.pass || index(nft, '65000') >= 0)
 die('scoped apply imported unrelated settings or lost outbound');
print('PASS: scoped Apply preserves actual credentials, outbound, DNS and firewall globals\n');
// A genuine direct receiver detects packets escaping during actual coordinator work.
let corp = corporateRuntime(sh), seed = corp.read();
seed.policies.corp_native.route = 'proxy';
if (corp.install(seed.rules, seed.policies, 'packet-seed') != null) die('cannot seed proxy');
function probe() {
 let result = sh.runCapture("ip netns exec mb-apply-client curl --disable --noproxy '*' -s --max-time 2 -o /dev/null -w '%{http_code}' http://8.8.8.8:18081/");
 if (!result.ok || result.out != '204') die('proxy packet did not traverse synthetic VPN: ' + result.out);
}
probe();
function packets() {
 return popen("exec timeout 22 sh -c 'i=0; while [ \"$i\" -lt 120 ]; do ip netns exec mb-apply-client curl --disable --noproxy \"*\" -s --max-time 0.1 -o /dev/null http://8.8.8.8:18081/ || true; i=$((i+1)); ucode -e \"require(\\\"socket\\\").poll(20)\"; done'");
}
function noDirect(traffic) {
 traffic.read('all'); traffic.close();
 if (length(readfile('/tmp/mb-direct-contacts') || '')) die('corporate proxy leaked a direct packet');
}
// External reload adds B and renames A. A's actual proxy decision must survive.
let traffic = packets();
for (let rule in [{ id: 'corp_native', name: 'Renamed', address: '8.8.8.8', port: '18081' },
 { id: 'corp_added', name: 'Added', address: '8.8.4.4', port: '443' }]) {
 c.set('monkey-business', rule.id, 'corporate_tunnel');
 for (let key in ['name', 'address', 'port']) c.set('monkey-business', rule.id, key, rule[key]);
 c.set('monkey-business', rule.id, 'enabled', '1'); c.set('monkey-business', rule.id, 'requires_udp', '0');
}
c.commit('monkey-business');
let reload = sh.runCapture('timeout 20 /etc/init.d/monkey-business reload');
noDirect(traffic);
if (!reload.ok || corp.read().policies.corp_native.route != 'proxy') die('external edit changed unchanged proxy policy');
probe();
print('PASS: external reload preserves unchanged proxy with concurrent LAN traffic and no direct contacts\n');
let predecessor = readfile('/etc/monkey-business/xray.json');
before = rt.routingSnapshot(); candidate = before.candidate; candidate.mode = 'gfwlist'; candidate.corporate_rules[0].enabled = false;
traffic = packets();
result = applyRouting({ ...rt, commitRouting: function() { sh.runCapture('sleep 1'); return 'synthetic_commit_failure'; } },
 { expected_revision: before.revision, request_id: nonce(), candidate: candidate });
if (result.error != 'apply_failed' || readfile('/etc/monkey-business/xray.json') != predecessor || loadApplied().config.global.routing_mode != 'gfwlist')
 die('real compensation failed: ' + sprintf('%J', result));
noDirect(traffic); probe();
print('PASS: commit failure with concurrent LAN packets compensates actual process, config, nft, UCI and snapshot\n');
// A release failure after durable success must be overwritten by the final
// rolled-back result, even after a later successful request clears error state.
let failedRelease = false;
let faultSh = { ...sh, runCapture: function(command) {
 if (!failedRelease && index(command, '/transition-end-') >= 0) { failedRelease = true; return { ok: false, out: '' }; }
 return sh.runCapture(command);
} };
let releaseRt = routingRuntime(faultSh, fresh, app, function() { return listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800) != null; });
let releaseBefore = releaseRt.routingSnapshot(), failedId = nonce();
let releaseCandidate = { ...releaseBefore.candidate, mode: 'global' };
let releaseArgs = { expected_revision: releaseBefore.revision, request_id: failedId, candidate: releaseCandidate };
traffic = packets();
let releaseResult = applyRouting(releaseRt, releaseArgs);
noDirect(traffic); probe();
if (releaseResult.error != 'apply_failed' || privateJson('/tmp/mb-runtime/routing-error.json', 4096) != null ||
 applyRouting(releaseRt, releaseArgs).error != 'apply_failed') die('release failure was not durably compensated');
let afterRelease = releaseRt.routingSnapshot();
let subsequent = applyRouting(releaseRt, { expected_revision: afterRelease.revision, request_id: nonce(), candidate: afterRelease.candidate });
if (subsequent.error != null || applyRouting(releaseRt, releaseArgs).error != 'apply_failed') die('old request resurrected a cancelled success');
print('PASS: transition release failure rolls back under traffic and same request ID cannot resurrect success\n');
let corporate = corporateRuntime(sh), currentPolicy = corporate.read(), returnedAt = int(monotonic()) - 10;
currentPolicy.policies.corp_native.route = 'proxy'; currentPolicy.policies.corp_native.last_return = returnedAt;
if (corporate.install(currentPolicy.rules, currentPolicy.policies, 'synthetic-return') != null) die('cannot seed actual policy');
if (!sh.runCapture('timeout 15 /etc/init.d/monkey-business stop').ok) die('recovery stop failed');
let stoppedPolicy = corporate.read();
if (stoppedPolicy.policies.corp_native.route != 'direct' || stoppedPolicy.policies.corp_native.last_return != returnedAt || stoppedPolicy.policies.corp_native.outbound != loadApplied().generation) die('stop lost policy identity/cooldown: ' + sprintf('%J', [stoppedPolicy, returnedAt, loadApplied().generation]));
let external = sh.runCapture('timeout 20 /etc/init.d/monkey-business start 2>&1');
if (!external.ok) die('external recovery start failed: ' + external.out);
let waitUntil = monotonic() + 5;
while (listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800) == null && monotonic() < waitUntil) require('socket').poll(20);
let startedPolicy = corporate.read();
if (startedPolicy.policies.corp_native.route != 'direct' || startedPolicy.policies.corp_native.last_return != returnedAt ||
 index(sh.runCapture('nft list set inet monkey_business corp_exact_direct').out, '8.8.8.8') < 0) die('recovery restart lost actual direct/cooldown');
print('PASS: recovery stop/start retains identity and cooldown with consistent nft snapshot\n');
function token() {
 let a = loadApplied(); return sprintf('%J', [a.generation, a.epoch, privateJson('/tmp/mb-runtime/intent.json', 4096)]);
}
let staleToken = token(), originalOwner = listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800);
storeApplied(loadApplied().config, loadApplied().generation);
let stale = sh.runCapture('timeout 5 ucode /usr/share/monkey-business/recovery-action.uc 0 ' + sh.shq(staleToken));
if (!stale.ok || sprintf('%J', listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800)) != sprintf('%J', originalOwner)) die('stale recovery signalled current engine');
let bin = '/tmp/mb-runtime/test-bin'; privateDirectory(bin);
atomicPrivate(bin + '/ubus', '#!/bin/sh\nprintf \'%s\' \'{"error":"synthetic_failure"}\'\n'); chmod(bin + '/ubus', 0o700);
let rejected = sh.runCapture('PATH=' + bin + ':$PATH timeout 5 ucode /usr/share/monkey-business/recovery-action.uc 3 ' + sh.shq(token()));
if (rejected.ok || sprintf('%J', listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800)) != sprintf('%J', originalOwner)) die('transport success accepted application failure');
let acceptedToken = token();
atomicPrivate(bin + '/ubus', '#!/bin/sh\nucode -e ' + sh.shq("import { loadApplied, storeApplied } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/applied.uc'; let a = loadApplied(); storeApplied(a.config, a.generation);") +
 '\nprintf \'%s\' ' + sh.shq(sprintf('%J', { ok: true, runtime_fence: acceptedToken })) + '\n'); chmod(bin + '/ubus', 0o700);
let replaced = sh.runCapture('PATH=' + bin + ':$PATH timeout 5 ucode /usr/share/monkey-business/recovery-action.uc 3 ' + sh.shq(acceptedToken));
if (!replaced.ok || sprintf('%J', listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800)) != sprintf('%J', originalOwner)) die('recovery adopted newer runtime fence');
print('PASS: stale recovery decision, application error and replaced response cannot stop current engine\n');
let faultBin = '/tmp/mb-runtime/fault-bin'; privateDirectory(faultBin);
atomicPrivate(faultBin + '/nft', '#!/bin/sh\n[ "$1" != delete ] || exit 1\nexec /usr/sbin/nft "$@"\n'); chmod(faultBin + '/nft', 0o700);
let lastPolicy = corporate.read(); lastPolicy.policies.corp_native.route = 'proxy';
if (corporate.install(lastPolicy.rules, lastPolicy.policies, 'synthetic-before-off') != null) die('cannot seed Off policy');
c.set('monkey-business', 'global', 'enabled', '0'); c.commit('monkey-business');
let failedStop = sh.runCapture('PATH=' + faultBin + ':$PATH timeout 15 /etc/init.d/monkey-business stop');
if (failedStop.ok || listenerOwner('/sys/fs/cgroup/monkey-business-engines/live', 11800) != null ||
 corporate.read().policies.corp_native.route != 'proxy' || !sh.runCapture('nft list table inet monkey_business').ok)
 die('failed Off cleanup was hidden or published as direct');
print('PASS: Off reports nft cleanup failure, stops engines and preserves last applied policy\n');
c.set('monkey-business', 'global', 'enabled', '0'); c.commit('monkey-business');
if (!sh.runCapture('timeout 10 /etc/init.d/monkey-business stop').ok) die('real stop failed');
if (sh.runCapture('nft list table inet monkey_business 2>/dev/null').ok) die('Off retained interception table');
print('PASS: Off removes the actual interception table\n');
