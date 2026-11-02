import { popen, lsdir, unlink, rmdir } from 'fs';
import { nonce, privateDirectory, privateJson, atomicPrivate } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { healthContext } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/health-context.uc';
import { sameContext } from '/usr/share/rpcd/ucode/lib/monkey-business/lib/health.uc';
import { acquireSlots, releaseSlots } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/probe-slots.uc';
import { monotonic } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/routing-v2.uc';
import * as uci from 'uci';
let directory = '/tmp/mb-runtime/leak/' + nonce(), slots = null, children = [], before;
try {
	if (!privateDirectory(directory)) die('directory_failed');
	before = healthContext(function() { return uci.cursor(); });
	if (before == null || !before.enabled || before.missing) die('not_running');
	slots = acquireSlots('manual', true);
	if (slots == null) die('slots_busy');
	for (let kind in ['direct', 'proxy']) {
		let path = directory + '/' + kind + '.json';
		if (!atomicPrivate(path, sprintf('%J', { proxy: kind == 'proxy' ? { ...before.live, ...before.applied.config.health } : false, directory: directory }))) die('write_failed');
		let child = popen('exec timeout 8 ucode /usr/share/monkey-business/exit-one.uc ' + path);
		if (child == null) die('spawn_failed');
		push(children, child);
	}
	let results = [];
	for (let child in children) {
		let output = child.read('all'), code = child.close();
		push(results, code == 0 ? json(output) : { error: 'method_failed' });
	}
	let after = healthContext(function() { return uci.cursor(); });
	if (after != null && after.enabled && sameContext(before.context, after.context)) {
		let valid = results[0].error == null && results[1].error == null;
		atomicPrivate('/tmp/mb-runtime/leak.json', sprintf('%J', { context: before.context, measured: monotonic(),
			state: valid ? (results[0].ip == results[1].ip ? 'leak' : 'clear') : 'unknown',
			reason: valid ? null : 'exit_probe_failed' }));
	}
} catch (e) { /* Failure/stale output is never a new leak diagnosis. */ }
if (slots != null) releaseSlots(slots);
for (let file in (lsdir(directory) || [])) unlink(directory + '/' + file);
rmdir(directory);
