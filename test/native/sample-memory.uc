// RSS is an intentionally conservative sum (shared mappings may be counted twice).
import { readfile, lsdir } from 'fs';
import * as socket from 'socket';
import { privateJson, atomicPrivate } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { processIdentity } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/listener.uc';
let id = ARGV[0], worker = int(ARGV[1]), path = '/tmp/mb-runtime/jobs/' + id, peak = 0, samples = 0;
if (match(id || '', /^[a-f0-9]{32}$/) == null || worker < 2) exit(1);
for (let tick = 0; tick < 4900; tick++) {
	let pids = {}; pids[worker] = true;
 function members(group) {
  for (let raw in split(readfile(group + '/cgroup.procs') || '', '\n'))
   if (match(raw, /^[0-9]+$/) != null) pids[int(raw)] = true;
  for (let name in (lsdir(group) || [])) if (match(name, /^node-[0-9]+$/) != null) members(group + '/' + name);
 }
 members('/sys/fs/cgroup/monkey-business-engines/job-' + id);
	for (let name in (lsdir(path) || [])) {
		if (match(name, /^\.owned-[0-9]+-[0-9]+$/) == null) continue;
		let owner = privateJson(path + '/' + name, 4096);
		if (owner != null && processIdentity(owner.pid) == owner.identity) pids[owner.pid] = true;
	}
	let total = 0;
	for (let pid in pids) {
		let rss = match(readfile('/proc/' + pid + '/status') || '', /VmRSS:[[:space:]]+([0-9]+) kB/);
		if (rss != null) total += int(rss[1]) * 1024;
	}
	peak = max(peak, total); samples++;
	let job = privateJson(path + '/status.json', 1048576);
	if (job != null && job.cleanup_done) break;
	socket.poll(50);
}
atomicPrivate(path + '/memory-test.json', sprintf('%J', { rss_peak_bytes: peak, samples: samples }));
