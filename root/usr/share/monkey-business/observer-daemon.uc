import * as uci from 'uci';
import * as socket from 'socket';
import { privateDirectory } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { observer } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/observer.uc';
import { monotonic } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/routing-v2.uc';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
if (!privateDirectory('/tmp/mb-runtime') || !privateDirectory('/tmp/mb-runtime/uci')) exit(1);
function freshCursor() { return uci.cursor('/etc/config', '/tmp/mb-runtime/uci'); }
let monitor = observer(sh, freshCursor);
while (true) {
	let started = monotonic();
	monitor.tick();
	// No catch-up rounds after a slow/stalled operation.
	let next = max(started + 15, monotonic());
	while (monotonic() < next) socket.poll(min(200, int((next - monotonic()) * 1000)));
}
