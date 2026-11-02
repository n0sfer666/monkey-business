import { unlink } from 'fs';
import { privateDirectory, atomicPrivate, nonce } from './private-store.uc';
import { runCapture, stripExit } from './shell.uc';

let cache = [], bytes = 0;
function fingerprint(value) {
	let body = sprintf('%J', value);
	for (let entry in cache) if (entry.body == body) return entry.hash;
	const dir = '/tmp/mb-runtime';
	if (!privateDirectory(dir)) die('unsafe_runtime_directory');
	let file = dir + '/hash-' + nonce();
	if (!atomicPrivate(file, body)) die('fingerprint_write_failed');
	let result = runCapture('sha256sum ' + file);
	unlink(file);
	let hash = match(stripExit(result.out), /^([a-f0-9]{64}) /);
	if (!result.ok || hash == null) die('fingerprint_failed');
	if (length(body) <= 65536) {
		push(cache, { body: body, hash: hash[1] }); bytes += length(body);
		while (length(cache) > 256 || bytes > 4194304) { let old = shift(cache); bytes -= length(old.body); }
	}
	return hash[1];
}
export { fingerprint };
