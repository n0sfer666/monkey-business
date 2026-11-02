// A process-independent global pool: two slots per node/observer round, eight total.
import { open, lstat } from 'fs';
import { privateDirectory } from './private-store.uc';
const ROOT = '/tmp/mb-runtime/slots';
function releaseSlots(handles) { for (let handle in handles) handle.close(); }
function acquireSlots(purpose, enabled) {
	if (!privateDirectory('/tmp/mb-runtime') || !privateDirectory(ROOT)) return null;
	let starts = purpose == 'observer' ? [6] : (enabled ? [0, 2, 4] : [0, 2, 4, 6]);
	for (let start in starts) {
		let handles = [];
		for (let index_ in [start, start + 1]) {
			let path = ROOT + '/' + index_;
			let before = lstat(path);
			if (before != null && (before.type != 'file' || before.uid != 0 || (before.mode & 0o077))) break;
			let handle = open(path, 'ae', 0o600);
			if (handle == null) break;
			if (!handle.lock('xn')) { handle.close(); break; }
			push(handles, handle);
		}
		if (length(handles) == 2) return handles;
		releaseSlots(handles);
	}
	return null;
}
export { acquireSlots, releaseSlots };
