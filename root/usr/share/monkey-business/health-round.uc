import { popen, unlink } from 'fs';
import { privateJson, atomicPrivate } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { probeUdp } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/udp-probe.uc';
import { aggregate } from '/usr/share/rpcd/ucode/lib/monkey-business/lib/health.uc';
let path = ARGV[0] || '';
if (match(path, /^\/tmp\/mb-runtime\/observer\/[a-f0-9]{32}\/request.json$/) == null) exit(1);
let request = privateJson(path, 32768);
if (request == null) exit(1);
let pending = [], outcomes = [], directory = substr(path, 0, length(path) - 13);
for (let i = 0; i < 2; i++) {
	let file = directory + '/target-' + i + '.json';
	if (!atomicPrivate(file, sprintf('%J', { diagnostic: request.diagnostic, target: request.targets[i], directory: directory }))) exit(1);
	push(pending, { path: file, child: popen('exec timeout 8 ucode /usr/share/monkey-business/https-one.uc ' + file) });
}
for (let task in pending) {
	let outcome = null;
	if (task.child != null) {
		let output = task.child.read('all'), code = task.child.close();
		try { outcome = code == 0 ? json(output) : null; } catch (e) {}
	}
	push(outcomes, outcome || { state: 'engine_error' }); unlink(task.path);
}
let udp = probeUdp(request.diagnostic);
print(sprintf('%J', { https: aggregate(outcomes), partial: (outcomes[0].state == 'success') != (outcomes[1].state == 'success'),
	udp: udp.state, udp_partial: udp.partial, targets: outcomes }));
