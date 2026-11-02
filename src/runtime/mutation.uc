// Advisory lock released by the kernel on crash; never held during network probes.
import { open, lstat } from 'fs';
import { privateDirectory } from './private-store.uc';
const DIR = '/tmp/mb-runtime';
function acquireMutation() {
	if (!privateDirectory(DIR)) return null;
	let path = DIR + '/mutation.lock';
	let existing = lstat(path);
	if (existing != null && (existing.type != 'file' || existing.uid != 0 || (existing.mode & 0o077)))
		return null;
	let handle = open(path, 'ae', 0o600);
	if (handle == null) return null;
	if (!handle.lock('xn')) { handle.close(); return null; }
	return handle;
}
export { acquireMutation };
