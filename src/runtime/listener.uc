// Verify ownership before disclosing generated SOCKS credentials to a listener.
import { readfile, lsdir, readlink, lstat } from 'fs';
function processIdentity(pid) {
	if (type(pid) != 'int' || pid <= 1) return null;
	let raw = readfile('/proc/' + pid + '/stat');
	if (raw == null) return null;
	let end = rindex(raw, ') ');
	if (end < 0) return null;
	let fields = split(substr(raw, end + 2), ' ');
	return fields[19];
}
function ownsListener(pid, identity, port) {
	if (processIdentity(pid) != identity || identity == null || type(port) != 'int') return false;
	let proc = '/proc/' + pid;
	let st = lstat(proc);
	if (st == null || st.uid != 0) return false;
	let address = sprintf('0100007F:%04X', port), inodes = {};
	for (let line in split(readfile('/proc/net/tcp') || '', '\n')) {
		let fields = split(trim(line), /[[:space:]]+/);
		if (fields[1] == address && fields[3] == '0A' && fields[7] == '0') inodes[fields[9]] = true;
	}
	for (let fd in (lsdir(proc + '/fd') || [])) {
		let socket = match(readlink(proc + '/fd/' + fd) || '', /^socket:\[([0-9]+)\]$/);
		if (socket != null && exists(inodes, socket[1])) return true;
	}
	return false;
}
export { processIdentity, ownsListener };
