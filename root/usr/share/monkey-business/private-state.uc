// Used by legacy shell workers too: no stat CLI dependency, no symlink-following.
import { mkdir, lstat, chmod, open, rename, unlink, readfile } from 'fs';
let operation = ARGV[0], path = ARGV[1] || '';
if (substr(path, 0, 1) != '/' || match(path, /(^|\/)\.\.?($|\/)/) != null) exit(1);
function directory(path) {
	let prefix = '';
	for (let part in split(path, '/')) {
		if (part == '') continue;
		prefix += '/' + part;
		let st = lstat(prefix);
		if (st == null) { mkdir(prefix, 0o700); st = lstat(prefix); }
		if (st == null || st.type != 'directory' || st.uid != 0 ||
			(prefix != '/tmp' && (st.mode & 0o022))) return false;
	}
	return chmod(path, 0o700);
}
if (operation == 'dir') exit(directory(path) ? 0 : 1);
let parent = replace(path, /\/[^/]+$/, '');
if (!directory(parent)) exit(1);
let old = lstat(path);
if (old != null && (old.type != 'file' || old.uid != 0)) exit(1);
if (operation == 'check') exit(0);
if (operation != 'write') exit(1);
let bytes = readfile('/dev/urandom', 16), token = '';
if (bytes == null || length(bytes) != 16) exit(1);
for (let i = 0; i < 16; i++) token += sprintf('%02x', ord(bytes, i));
let temporary = parent + '/.state-' + token, file = open(temporary, 'wxe', 0o600);
if (file == null) exit(1);
let data = readfile('/dev/stdin', 4096);
if (data == null || file.write(data + '\n') != length(data) + 1 || !file.close() || !rename(temporary, path)) {
	unlink(temporary); exit(1);
}
