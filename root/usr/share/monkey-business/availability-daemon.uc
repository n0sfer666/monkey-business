// One procd instance owns the queue independently of rpcd and browser lifetimes.
import * as uci from 'uci';
import { readfile } from 'fs';
import * as socket from 'socket';
import { privateDirectory } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { processIdentity } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/listener.uc';
import { currentJob, finishJob, boot, reapOrphans } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/jobs.uc';
import { runJob } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/availability-worker.uc';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
import { monotonic } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/routing-v2.uc';
if (!privateDirectory('/tmp/mb-runtime')) exit(1);
let pid = int(split(readfile('/proc/self/stat'), ' ')[0]), identity = processIdentity(pid);
function enabled() { let c = uci.cursor(); return c.get('monkey-business', 'global', 'enabled') == '1'; }
while (true) {
	reapOrphans();
	let job = currentJob();
	if (job != null) {
		if (job.boot != boot()) finishJob(job, 'failed', 'reboot');
		else if (job.worker != null && (job.worker.pid != pid || job.worker.identity != identity))
			finishJob(job, 'failed', 'worker_crash');
		else if (monotonic() >= job.deadline) finishJob(job, 'incomplete', 'deadline');
		else if (job.cleanup_done === false && index(['completed', 'cancelled', 'incomplete', 'failed'], job.state) >= 0) finishJob(job, 'failed', 'cleanup_retry');
		else if (job.state == 'queued') runJob(sh, job, enabled, { pid: pid, identity: identity });
	}
	socket.poll(200);
}
