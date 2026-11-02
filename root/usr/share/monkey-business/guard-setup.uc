import { readfile, lstat, mkdir } from 'fs';
const GROUP = '/sys/fs/cgroup/monkey-business-engines';
const STATE = '/tmp/mb-runtime';
let mounts = readfile('/proc/self/mountinfo') || '';
let supported = false;
for (let line in split(mounts, '\n'))
	if (index(line, ' /sys/fs/cgroup ') >= 0 && index(line, ' - cgroup2 ') >= 0) supported = true;
if (!supported) { warn('cgroup v2 required\n'); exit(1); }
mkdir(GROUP, 0o755); mkdir(GROUP + '/live', 0o755); mkdir(STATE, 0o700);
if (lstat(GROUP + '/live/cgroup.kill') == null) { warn('cgroup.kill required\n'); exit(1); }
let group = lstat(GROUP), state = lstat(STATE);
if (group == null || group.type != 'directory' || group.uid != 0 || (group.mode & 0o022) ||
	state == null || state.type != 'directory' || state.uid != 0 || (state.mode & 0o077)) {
	warn('unsafe diagnostic guard directories\n'); exit(1);
}

let mutation = lstat(STATE + '/mutation.lock');
if (mutation != null && (mutation.type != 'file' || mutation.uid != 0 || (mutation.mode & 0o077))) {
	warn('unsafe mutation lock\n'); exit(1);
}
// Never impose our port ACL on an unrelated pre-existing service.
let inodes = {};
for (let protocol in ['tcp', 'tcp6', 'udp', 'udp6']) {
	for (let line in split(readfile('/proc/net/' + protocol) || '', '\n')) {
		let fields = split(trim(line), /[[:space:]]+/), address = split(fields[1] || '', ':');
		let port = length(address) == 2 ? hex(address[1]) : 0;
		if ((port >= 10808 && port <= 10811) || (port >= 11800 && port <= 12263)) {
			if (index(protocol, 'tcp') == 0 && fields[3] != '0A') continue;
			inodes[fields[9]] = true;
		}
	}
}
if (length(keys(inodes))) {
	let fs = require('fs');
	for (let name in (fs.lsdir('/proc') || [])) {
		if (match(name, /^[0-9]+$/) == null) continue;
		for (let fd in (fs.lsdir('/proc/' + name + '/fd') || [])) {
			let socket = match(fs.readlink('/proc/' + name + '/fd/' + fd) || '', /^socket:\[([0-9]+)\]$/);
			if (socket == null || !exists(inodes, socket[1])) continue;
			let group = readfile('/proc/' + name + '/cgroup') || '';
			if (index(group, '0::/monkey-business-engines/') != 0) {
				warn('reserved diagnostic port occupied outside the owned cgroup\n'); exit(1);
			}
			delete inodes[socket[1]];
		}
	}
}

if (length(keys(inodes))) { warn('reserved socket owner unknown\n'); exit(1); }
