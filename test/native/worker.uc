import { readRecords } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/availability-records.uc';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
import { enqueue, readJob, jobStatus, boot, finishJob, writeJob, jobPath, reapOrphans } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/jobs.uc';
import { runJob } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/availability-worker.uc';
import { processIdentity } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/listener.uc';
import { readfile, lsdir, popen, mkdir } from 'fs';
import { atomicPrivate, privateDirectory, privateJson, nonce } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
import { shortProbeResult } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/short-probe.uc';
import { monotonic } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/routing-v2.uc';
let servers = [];
for (let i = 0; i < 50; i++) push(servers, { tag: 'synthetic-' + i, source: 'manual', protocol: 'vless',
	address: '10.0.2.2', port: 14080, uuid: '11111111-2222-3333-4444-555555555555',
	encryption: 'none', security: 'none', transport: { type: 'tcp' } });
let targets = [{ url: 'https://one.fixture.example:18443/ok', expected_status: 204 },
	{ url: 'https://two.fixture.example:18443/ok', expected_status: 204 }];
let result = enqueue(servers, { scope: 'all' }, { targets: targets, dns: {}, revision: 'synthetic' }, 'synthetic-network');
if (result.error != null) die('enqueue: ' + result.error);
let pid = int(split(readfile('/proc/self/stat'), ' ')[0]), start = monotonic();
let sampler = popen('exec timeout 245 ucode /tmp/mb-native/test/native/sample-memory.uc ' + result.job_id + ' ' + pid);
runJob(sh, readJob(result.job_id), function() { return true; }, { pid: pid, identity: processIdentity(pid) });
sampler.read('all'); sampler.close();
let memory = privateJson(jobPath(result.job_id) + '/memory-test.json', 4096);
if (memory == null || memory.rss_peak_bytes > 268435456) die('memory budget exceeded');
let job = readJob(result.job_id);
print(sprintf('%J\n', { state: job.state, reason: job.reason, counts: jobStatus({ job_id: result.job_id, offset: 0, limit: 50 }).counts,
	completed: job.completed, total: job.total, elapsed: monotonic() - start, cleanup: job.cleanup_done, metrics: job.metrics, memory: memory }));
if (job.state != 'completed' || job.completed != 50 || !job.cleanup_done) die('job did not complete');
for (let row in job.rows) if (row.state != 'available' || row.successes != 2) die('unexpected HTTPS outcome: ' + row.state);
if (length(filter(lsdir('/sys/fs/cgroup/monkey-business-engines'), function(name) { return index(name, 'job-') == 0; }))) die('orphan cgroup');
print('PASS: native 50-node real VPN worker, HTTPS, pagination and kernel cleanup\n');

let confirmation = shortProbeResult(sh, {}, servers[0], targets);
if (!confirmation.ok) die('short confirmation failed: ' + confirmation.reason);
print('PASS: shared short confirmation and owned cleanup\n');
// Cancel after actual probes have started; an unrelated listener must survive.
let cancelled = enqueue(servers, { scope: 'all' }, { targets: [{ ...targets[0], url: 'https://one.fixture.example:18443/slow' },
	{ ...targets[1], url: 'https://two.fixture.example:18443/slow' }], dns: {}, revision: 'slow' }, 'synthetic-network');
let cancel = popen('sleep 2; umask 077; printf cancel > ' + jobPath(cancelled.job_id) + '/cancel');
runJob(sh, readJob(cancelled.job_id), function() { return true; }, { pid: pid, identity: processIdentity(pid) });
cancel.close();
let cancelledJob = readJob(cancelled.job_id);
if (cancelledJob.state != 'cancelled' || !cancelledJob.cleanup_done) die('cancel cleanup failed');
print('PASS: cancellation during bounded HTTPS and all owned processes cleaned\n');
// Cancel specifically while a new leader awaits its extra request. A prior
// completed record must retain the original base timestamp through job rotation.
let slowExtra = map(targets, function(target) { return { ...target, url: replace(target.url, '/ok', '/extra-slow') }; });
let completedExtra = enqueue([servers[0]], { scope: 'all' }, { targets: slowExtra, dns: {}, revision: 'extra-cancel' }, 'synthetic-network');
runJob(sh, readJob(completedExtra.job_id), function() { return true; }, { pid: pid, identity: processIdentity(pid) });
let previousRecord = filter(readRecords(), function(row) { return row.server_ref.tag == servers[0].tag; })[0];
if (previousRecord == null || previousRecord.state != 'degraded') die('extra negative control did not complete');
let duringExtra = enqueue([servers[0]], { scope: 'all' }, { targets: slowExtra, dns: {}, revision: 'extra-cancel' }, 'synthetic-network');
let extraCanceller = popen('exec timeout 15 ucode /tmp/mb-native/test/native/cancel-extra.uc ' + duringExtra.job_id);
runJob(sh, readJob(duringExtra.job_id), function() { return true; }, { pid: pid, identity: processIdentity(pid) });
let extraOutput = extraCanceller.read('all'), extraCode = extraCanceller.close();
let afterRecord = filter(readRecords(), function(row) { return row.server_ref.tag == servers[0].tag; })[0];
if (extraCode != 0 || extraOutput != 'cancelled-extra' || readJob(duringExtra.job_id).state != 'cancelled' ||
 sprintf('%J', afterRecord) != sprintf('%J', previousRecord)) die('extra cancel replaced completed result');
print('PASS: cancel during extra preserves the completed node result and original base timestamp\n');

// Recovery preemption consumes the absolute budget without starting new probes.
let preempted = enqueue([servers[0]], { scope: 'all' }, { targets: targets, dns: {}, revision: 'synthetic' }, 'synthetic-network');
let pending = readJob(preempted.job_id); pending.deadline = monotonic() + 12; writeJob(pending);
atomicPrivate('/tmp/mb-runtime/recovery.json', '{"active":true}');
runJob(sh, pending, function() { return true; }, { pid: pid, identity: processIdentity(pid) });
atomicPrivate('/tmp/mb-runtime/recovery.json', '{"active":false}');
let preemptedJob = readJob(preempted.job_id);
if (preemptedJob.state != 'incomplete' || preemptedJob.reason != 'recovery_preemption' || !preemptedJob.cleanup_done) die('preemption budget failed');
print('PASS: recovery preemption does not extend the job deadline\n');

let hyServer = { tag: 'synthetic-hy', source: 'manual', protocol: 'hysteria2', address: '10.0.2.2', port: 14443,
 password: 'synthetic', sni: 'one.fixture.example', insecure: '1' };
// Only the isolated fixture's self-signed QUIC certificate is skipped. HTTPS target
// certificates still use the synthetic CA and strict production probe validation.
let hyJob = enqueue([hyServer], { scope: 'all' }, { targets: targets, dns: {}, revision: 'hy' }, 'synthetic-network');
runJob(sh, readJob(hyJob.job_id), function() { return true; }, { pid: pid, identity: processIdentity(pid) });
let hyResult = readJob(hyJob.job_id);
if (hyResult.state != 'completed' || hyResult.rows[0].successes != 2 || !hyResult.cleanup_done) die('Hysteria worker failed: ' + sprintf('%J', hyResult));
print('PASS: real Hysteria bridge, authenticated SOCKS, strict HTTPS and temporary cleanup\n');

let crashed = enqueue(slice(servers, 0, 4), { scope: 'all' }, { targets: [{ ...targets[0], url: 'https://one.fixture.example:18443/slow' },
 { ...targets[1], url: 'https://two.fixture.example:18443/slow' }], dns: {}, revision: 'crash' }, 'synthetic-network');
let killer = popen('exec timeout 12 ucode /tmp/mb-native/test/native/crash-node.uc ' + crashed.job_id);
runJob(sh, readJob(crashed.job_id), function() { return true; }, { pid: pid, identity: processIdentity(pid) });
let killed = killer.read('all'), killerCode = killer.close(), crashedJob = readJob(crashed.job_id);
if (killerCode != 0 || killed != 'killed-owned-node' || !crashedJob.cleanup_done || crashedJob.rows[0].state != 'engine_error')
 die('crashed-node cleanup failed: ' + sprintf('%J', [killerCode, killed, crashedJob]));
if (length(filter(lsdir('/sys/fs/cgroup/monkey-business-engines'), function(name) { return index(name, 'job-') == 0; }))) die('crashed node orphan');
print('PASS: node leader crash kills detached probes before probe slots are reused\n');
