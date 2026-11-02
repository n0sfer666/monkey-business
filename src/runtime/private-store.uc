// Private runtime files: fail closed on pre-existing symlinks or unsafe ownership.
import { mkdir, lstat, open, rename, unlink, readfile } from 'fs';

function privateDirectory(path) {
	mkdir(path, 0o700);
	let st = lstat(path);
	return st != null && st.type == 'directory' && st.uid == 0 &&
		(st.mode & 0o077) == 0;
}

function nonce() {
	let raw = readfile('/dev/urandom', 16);
	if (raw == null || length(raw) != 16) die('random_source_failed');
	let result = '';
	for (let i = 0; i < 16; i++) result += sprintf('%02x', ord(raw, i));
	return result;
}

function atomicPrivate(path, data) {
	// Callers supply internal paths inside an already verified root-owned directory.
	let parent = replace(path, /\/[^/]+$/, '');
	let st = lstat(parent);
	if (st == null || st.type != 'directory' || st.uid != 0 || (st.mode & 0o022) != 0)
		return false;
	let tmp = parent + '/.new-' + nonce();
	let file = open(tmp, 'wxe', 0o600);
	if (file == null) return false;
	let written = file.write(data);
	let closed = file.close();
	if (written != length(data) || !closed || !rename(tmp, path)) {
		unlink(tmp); return false;
	}
	return true;
}

function privateJson(path, limit) {
	let st = lstat(path);
	if (st == null || st.type != 'file' || st.uid != 0 || (st.mode & 0o077) != 0 || st.size > limit)
		return null;
	try { return json(readfile(path)); } catch (e) { return null; }
}

export { privateDirectory, nonce, atomicPrivate, privateJson };
