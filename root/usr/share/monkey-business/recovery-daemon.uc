import * as uci from 'uci';
import { readfile } from 'fs';
import * as socket from 'socket';
import { privateDirectory, privateJson, atomicPrivate } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { sameContext, fresh } from '/usr/share/rpcd/ucode/lib/monkey-business/lib/health.uc';
import { healthContext } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/health-context.uc';
import { recoveryStep } from '/usr/share/rpcd/ucode/lib/monkey-business/lib/recovery.uc';
import { readHealth } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/health-context.uc';
import { loadApplied } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/applied.uc';
import { monotonic } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/routing-v2.uc';
import { spawnOwned, finished, collect, stopOwned, cleanOwnedDirectory } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/owned-process.uc';
if (!privateDirectory('/tmp/mb-runtime') || !privateDirectory('/tmp/mb-runtime/recovery') || !privateDirectory('/tmp/mb-runtime/leak')) exit(1);
cleanOwnedDirectory('/tmp/mb-runtime/recovery');
cleanOwnedDirectory('/tmp/mb-runtime/leak');
let state = null, child = null, generation = null, kind = null, exitDue = 0, exitContext = null;
while (true) {
	let c = uci.cursor(), enabled = c.get('monkey-business', 'global', 'enabled') == '1';
	let applied = loadApplied(), health = readHealth(function() { return uci.cursor(); });
	if (applied == null || health == null || health.context.outbound != applied.generation || health.context.boot != trim(readfile('/proc/sys/kernel/random/boot_id')))
		health = null;
	let leak = privateJson('/tmp/mb-runtime/leak.json', 4096), current = healthContext(function() { return uci.cursor(); });
	let confirmedLeak = current != null && leak != null && sameContext(leak.context, current.context) &&
		monotonic() >= leak.measured && monotonic() - leak.measured <= 600 && leak.state == 'leak';
	if (child != null && kind == 'leak' && fresh(health, monotonic()) && health.https.state == 'down' && health.https.sample == 'failure') {
		stopOwned(child); child = null;
	}
	if (child != null && (!enabled || finished(child))) {
		if (!enabled) stopOwned(child); else collect(child);
		child = null;
	}
	if (child == null) {
		if (applied != null && generation != applied.generation) { state = null; generation = applied.generation; }
		state = recoveryStep(state, health, enabled, monotonic(), confirmedLeak);
		if (state.action != null) {
			kind = 'recovery';
			let expected = applied != null ? sprintf('%J', [applied.generation, applied.epoch, privateJson('/tmp/mb-runtime/intent.json', 4096)]) : '';
			child = spawnOwned(['ucode', '/usr/share/monkey-business/recovery-action.uc', state.action, expected], '/tmp/mb-runtime/recovery', 100);
			delete state.action;
			if (child.error != null) child = null;
		}
		if (child == null && enabled && current != null && !current.missing && (monotonic() >= exitDue || exitContext != sprintf('%J', current.context))) {
			kind = 'leak'; exitDue = monotonic() + 300; exitContext = sprintf('%J', current.context);
			child = spawnOwned(['ucode', '/usr/share/monkey-business/leak-round.uc'], '/tmp/mb-runtime/leak', 10);
			if (child.error != null) child = null;
		}
		let published = sprintf('%J', { ...state, active: (child != null && kind == 'recovery') || state.phase == 'reconnecting', leak: confirmedLeak });
		if (readfile('/tmp/mb-runtime/recovery.json') != published) atomicPrivate('/tmp/mb-runtime/recovery.json', published);
	}
	socket.poll(1000);
}
