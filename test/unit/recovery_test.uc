import { test, assertEq, run } from '../harness.uc';
import { recoveryStep } from '../../src/lib/recovery.uc';
import { initial, round } from '../../src/lib/health.uc';
let context = { boot: 'b', outbound: 'o', runtime: 'r', method: 'm', network: 'n' };
function down(now) {
	let h = round(initial(context), context, 'failure', 'success', now - 15);
	return round(h, context, 'failure', 'success', now);
}
test('two confirmed HTTPS failures invoke existing four-step ladder then bounded backoff', function() {
	let state = null;
	for (let i = 0; i < 4; i++) {
		state = recoveryStep(state, down(1 + i * 45), true, 1 + i * 45);
		assertEq(state.action, '' + i); delete state.action;
	}
	state = recoveryStep(state, down(181), true, 181);
	assertEq([state.phase, state.action, state.next], ['down', 'stop', 241]); delete state.action;
	assertEq(recoveryStep(state, down(200), true, 200).action, null);
	assertEq(recoveryStep(state, down(241), true, 241).action, 'retry');
});
test('UDP down, partial HTTPS, unknown or stale do not initiate general recovery', function() {
	let h = round(initial(context), context, 'success', 'failure', 1);
	h = round(h, context, 'success', 'failure', 16);
	assertEq(recoveryStep(null, h, true, 16).phase, 'healthy');
	assertEq(recoveryStep(null, down(16), true, 62).phase, 'healthy');
	h = round(down(16), context, 'unknown', 'failure', 31);
	assertEq(recoveryStep(null, h, true, 31).phase, 'healthy');
	assertEq(recoveryStep(null, down(16), false, 16).phase, 'off');
});
exit(run());
