// Run only after separately authorized installation, with a synthetic <=50-node scope.
// Reads process identities/status and job status; never reads UCI, definitions or credentials.
import { readfile, lsdir } from 'fs';
import * as socket from 'socket';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
import { privateJson } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { processIdentity } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/listener.uc';
function now() { return +split(readfile('/proc/uptime'), ' ')[0]; }
if (ARGV[0] != 'run-synthetic-all') { warn('Requires explicit run-synthetic-all, after hardware authorization\n'); exit(2); }
let roster = sh.runCapture('ubus call monkey-business servers_list');
let public_ = roster.ok ? json(roster.out) : null;
if (public_ == null || length(public_.servers || []) != 50) die('prepare_exactly_50_synthetic_nodes_before_start');
let start = now(), request = sh.runCapture('ubus call monkey-business availability_start \'{"scope":"all"}\'');
let response = request.ok ? json(request.out) : null;
if (response == null || match(response.job_id || '', /^[a-f0-9]{32}$/) == null) die('job_start_failed');
let path = '/tmp/mb-runtime/jobs/' + response.job_id, peak = 0, samples = 0, done = null;
while (now() - start <= 245) {
 let job = privateJson(path + '/status.json', 1048576), pids = {};
 if (job == null || job.total > 50) die('acceptance_requires_at_most_50_synthetic_nodes');
 if (job.worker != null && processIdentity(job.worker.pid) == job.worker.identity) pids[job.worker.pid] = true;
 function members(group) {
  for (let raw in split(readfile(group + '/cgroup.procs') || '', '\n'))
   if (match(raw, /^[0-9]+$/) != null) pids[int(raw)] = true;
  for (let name in (lsdir(group) || [])) if (match(name, /^node-[0-9]+$/) != null) members(group + '/' + name);
 }
 members('/sys/fs/cgroup/monkey-business-engines/job-' + response.job_id);
 for (let name in (lsdir(path) || [])) {
  if (match(name, /^\.owned-[0-9]+-[0-9]+$/) == null) continue;
  let owner = privateJson(path + '/' + name, 4096);
  if (owner != null && processIdentity(owner.pid) == owner.identity) pids[owner.pid] = true;
 }
 let rss = 0;
 for (let pid in pids) {
  let measured = match(readfile('/proc/' + pid + '/status') || '', /VmRSS:[[:space:]]+([0-9]+) kB/);
  if (measured != null) rss += int(measured[1]) * 1024;
 }
 peak = max(peak, rss); samples++;
 if (job.cleanup_done) { done = job; break; }
 socket.poll(50);
}
let elapsed = now() - start;
let passed = done != null && done.state == 'completed' && done.total == 50 && done.completed == 50 &&
 done.cleanup_done && elapsed <= 240 && peak <= 268435456;
print(sprintf('%J\n', { job_id: response.job_id, state: done != null ? done.state : 'timeout',
 completed: done != null ? done.completed : null, total: done != null ? done.total : null,
 cleanup_done: done != null ? done.cleanup_done : false, elapsed_seconds: elapsed,
 conservative_rss_peak_bytes: peak, samples: samples, kernel: trim(readfile('/proc/sys/kernel/osrelease')),
 budget_pass: passed }));
exit(passed ? 0 : 1);
