// Called after procd stop while the caller holds the mutation lock.
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
import { endTransition } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/corporate-transition.uc';
import { unlink, readfile } from 'fs';
import * as socket from 'socket';
import { declarations } from '/usr/share/rpcd/ucode/lib/monkey-business/generator/corporate-nft.uc';
import { privateJson, atomicPrivate } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/private-store.uc';
let end = +split(readfile('/proc/uptime'), ' ')[0] + 7;
while (length(trim(readfile('/sys/fs/cgroup/monkey-business-engines/live/cgroup.procs') || ''))) {
 if (+split(readfile('/proc/uptime'), ' ')[0] >= end) exit(1);
 socket.poll(20);
}
unlink('/tmp/mb-runtime/health.json');
if (ARGV[0] == '1') { atomicPrivate('/tmp/mb-runtime/routing-error.json', '{"error":"stop_failed"}'); exit(1); }
let policy = privateJson('/tmp/mb-runtime/corporate.json', 65536);
if (policy != null) {
 for (let id in policy.policies) policy.policies[id] = { ...policy.policies[id], route: 'direct', reason: 'vpn_off', reset: false };
 if (!atomicPrivate('/tmp/mb-runtime/corporate-sets.nft', declarations(policy.rules || [], policy.policies))) { unlink('/tmp/mb-runtime/corporate.json'); exit(1); }
 if (!atomicPrivate('/tmp/mb-runtime/corporate.json', sprintf('%J', policy))) { unlink('/tmp/mb-runtime/corporate.json'); exit(1); }
}

let error = privateJson('/tmp/mb-runtime/routing-error.json', 4096);
if (error != null && error.error == 'stop_failed') unlink('/tmp/mb-runtime/routing-error.json');

if (endTransition(sh) != null) exit(1);
