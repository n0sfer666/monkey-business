import { test, assertEq, run } from '../harness.uc';
import { readfile, unlink } from 'fs';
import { routingRuntime } from '../../src/runtime/routing-v2.uc';
import { privateDirectory, atomicPrivate, privateJson } from '../../src/runtime/private-store.uc';
let dir = '/tmp/mb-runtime', paths = ['routing-requests.json', 'routing-error.json', 'corporate-transition.json'], saved = {};
privateDirectory(dir);
for (let path in paths) { saved[path] = readfile(dir + '/' + path); unlink(dir + '/' + path); }
let fail = false, rt = routingRuntime({ runCapture: function() { return { ok: !fail }; } }, null, null, null);
test('production request cache upserts compensated result instead of resurrecting success', function() {
 rt.recordRequest('same-request', 'body', { ok: true, revision: 'cancelled' });
 rt.recordRequest('same-request', 'body', { error: 'apply_failed' });
 assertEq(length(privateJson(dir + '/routing-requests.json', 4194304)), 1);
 assertEq(rt.requestResult('same-request').result.error, 'apply_failed');
 rt.recordRequest('another-request', 'body', { ok: true });
 assertEq(rt.requestResult('same-request').result.error, 'apply_failed');
});
test('successful rollback barrier release clears its failure marker', function() {
 fail = true;
 assertEq(rt.finishRouting({ enabled: true }), 'transition_release_failed');
 assertEq(privateJson(dir + '/routing-error.json', 4096).error, 'rollback_failed');
 fail = false;
 assertEq(rt.finishRouting({ enabled: true }), null);
 assertEq(privateJson(dir + '/routing-error.json', 4096), null);
});
let rc = run();
for (let path in paths) { if (saved[path] == null) unlink(dir + '/' + path); else atomicPrivate(dir + '/' + path, saved[path]); }
exit(rc);
