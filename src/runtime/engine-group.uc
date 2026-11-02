// Kernel-owned job identity: cleanup cannot signal a reused foreign PID.
import { mkdir, lstat, readfile, open, rmdir, lsdir } from 'fs';
import * as socket from 'socket';
const ROOT = '/sys/fs/cgroup/monkey-business-engines';
function groupPath(id) {
	if (type(id) != 'string' || match(id, /^[a-f0-9]{32}$/) == null) return null;
	return ROOT + '/job-' + id;
}
function prepareGroup(id) {
	let path = groupPath(id);
	if (path == null) return null;
	mkdir(path, 0o755);
	let st = lstat(path), kill = lstat(path + '/cgroup.kill');
	if (st == null || st.type != 'directory' || st.uid != 0 || (st.mode & 0o022) || kill == null)
		return null;
	return path;
}
function nodePath(id, index_) {
	let parent = groupPath(id);
	return parent != null && type(index_) == 'int' && index_ >= 0 && index_ < 200 ? parent + '/node-' + index_ : null;
}
function prepareNode(id, index_) {
	let path = nodePath(id, index_);
	if (path == null || prepareGroup(id) == null) return null;
	mkdir(path, 0o755);
	let st = lstat(path);
	return st != null && st.type == 'directory' && st.uid == 0 && !(st.mode & 0o022) && lstat(path + '/cgroup.kill') != null ? path : null;
}
function joinGroup(id, index_) {
	let path = index_ != null ? prepareNode(id, index_) : prepareGroup(id);
	if (path == null) return false;
	let pid = split(readfile('/proc/self/stat'), ' ')[0];
	let file = open(path + '/cgroup.procs', 'w');
	if (file == null) return false;
	let ok = file.write(pid + '\n') == length(pid) + 1;
	return file.close() && ok;
}
function cleanPath(path) {
	if (path == null) return false;
	let st = lstat(path);
	if (st == null) return true;
	if (st.type != 'directory' || st.uid != 0 || (st.mode & 0o022)) return false;
	let file = open(path + '/cgroup.kill', 'w');
	if (file == null) return false;
	let ok = file.write('1\n') == 2;
	if (!file.close() || !ok) return false;
	for (let i = 0; i < 200; i++) {
		let events = readfile(path + '/cgroup.events');
		if (events != null && index(events, 'populated 0') >= 0) {
			for (let name in (lsdir(path) || [])) {
				if (match(name, /^node-[0-9]+$/) == null) continue;
				if (!rmdir(path + '/' + name)) return false;
			}
			return rmdir(path);
		}
		socket.poll(10);
	}
	return false;
}
function cleanGroup(id) { return cleanPath(groupPath(id)); }
function cleanNode(id, index_) { return cleanPath(nodePath(id, index_)); }
export { groupPath, nodePath, prepareGroup, prepareNode, joinGroup, cleanGroup, cleanNode };
