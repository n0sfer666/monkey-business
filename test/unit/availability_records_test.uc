import { test, assertEq, run } from '../harness.uc';
import { mergeRecord } from '../../src/runtime/availability-records.uc';
function row(tag, stamp, state, phase) { return { server_ref: { source: 'manual', tag: tag }, boot: 'boot', base_finished: stamp, state: state, phase: phase }; }
test('cancel during extra cannot replace a completed success or extend its timestamp', function() {
 let previous = row('node', 100, 'available');
 for (let pending in [row('node', 150, 'available', 'extra'), row('node', 150, 'cancelled'), row('node', 150, 'incomplete')])
  assertEq(mergeRecord([previous], pending, 160, 'boot'), [previous]);
 assertEq(mergeRecord([previous], row('node', 150, 'degraded'), 160, 'boot')[0].base_finished, 150);
});
test('record capacity and expiry are independent of retained or cancelled job count', function() {
 let records = [];
 for (let i = 0; i < 501; i++) push(records, row('node-' + i, 100 + i, 'available'));
 let result = mergeRecord(records, null, 610, 'boot');
 assertEq(length(result), 500); assertEq(result[0].server_ref.tag, 'node-500');
 assertEq(mergeRecord(result, null, 1300, 'boot'), []);
 assertEq(mergeRecord(result, null, 610, 'other-boot'), []);
});
exit(run());
