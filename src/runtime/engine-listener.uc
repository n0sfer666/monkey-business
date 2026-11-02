import { readfile } from 'fs';
import { ownsListener, processIdentity } from './listener.uc';
function listenerOwner(group, port) {
	for (let raw in split(trim(readfile(group + '/cgroup.procs') || ''), '\n')) {
		let pid = int(raw), identity = processIdentity(pid);
		if (ownsListener(pid, identity, port)) return { pid: pid, identity: identity };
	}
	return null;
}
function engineIdentities(group) {
 let out = [];
 for (let raw in split(trim(readfile(group + '/cgroup.procs') || ''), '\n')) {
  let pid = int(raw), identity = processIdentity(pid);
  if (identity != null) push(out, { pid: pid, identity: identity });
 }
 return out;
}
function acceptedOwner(owner, blocked, allowed) {
 if (owner == null) return false;
 function same(other) { return other != null && owner.pid == other.pid && owner.identity == other.identity; }
 if (same(allowed)) return true;
 for (let item in blocked) if (same(item)) return false;
 return true;
}
export { listenerOwner, engineIdentities, acceptedOwner };
