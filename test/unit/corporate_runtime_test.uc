import { test, assert, assertEq, run } from '../harness.uc';
import { readfile, rename, unlink } from 'fs';
import { corporateRuntime, DIR, POLICY, SETS } from '../../src/runtime/corporate.uc';
import { privateDirectory, atomicPrivate } from '../../src/runtime/private-store.uc';
assert(privateDirectory(DIR));
let saved = { policy: readfile(POLICY), sets: readfile(SETS) };
let rules = [{ id: 'synthetic', name: 'Synthetic', requires_udp: false, address: '8.8.8.8', port: '', enabled: true }];
function fixture(fault) {
 atomicPrivate(POLICY, sprintf('%J', { rules: rules, policies: { synthetic: { route: 'direct' } } }));
 atomicPrivate(SETS, 'old sets');
 let calls = [], writes = 0, renames = 0;
 let runtime = corporateRuntime({ runCapture: function(cmd) { push(calls, cmd); return { ok: fault != 'rollback' || length(calls) == 1 }; } }, {
  write: function(path, body) { writes++; return fault == 'prepare' && writes == 2 ? false : atomicPrivate(path, body); },
  rename: function(from, to) { renames++; return (fault == 'publish' || fault == 'rollback') && renames == 2 ? false : rename(from, to); }
 });
 return { runtime: runtime, calls: calls, before: readfile(POLICY) };
}
test('preparation failure leaves kernel and published policy untouched', function() {
 let f = fixture('prepare');
 assertEq(f.runtime.install(rules, { synthetic: { route: 'proxy' } }, 'new'), 'policy_preparation_failed');
 assertEq(length(f.calls), 0); assertEq(readfile(POLICY), f.before); assertEq(readfile(SETS), 'old sets');
});
test('publication failure compensates kernel and both snapshots', function() {
 let f = fixture('publish');
 assertEq(f.runtime.install(rules, { synthetic: { route: 'proxy' } }, 'new'), 'policy_snapshot_failed');
 assertEq(length(f.calls), 2); assert(index(f.calls[1], '.rollback') > 0);
 assertEq(readfile(POLICY), f.before); assertEq(readfile(SETS), 'old sets');
});
test('failed compensation invalidates policy rather than publishing an intention', function() {
 let f = fixture('rollback');
 assertEq(f.runtime.install(rules, { synthetic: { route: 'proxy' } }, 'new'), 'rollback_failed');
 assertEq(readfile(POLICY), null);
});
let rc = run();
if (saved.policy == null) unlink(POLICY); else atomicPrivate(POLICY, saved.policy);
if (saved.sets == null) unlink(SETS); else atomicPrivate(SETS, saved.sets);
exit(rc);
