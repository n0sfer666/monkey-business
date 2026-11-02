// Read APIs must not expose an offline verifier of passwords contained in revisions.
import { open, unlink } from 'fs';
import { privateDirectory, privateJson, nonce } from './private-store.uc';
import { fingerprint } from './fingerprint.uc';
function opaqueRevision(scope, value) {
	const PATH = '/tmp/mb-runtime/revision-key.json';
	if (!privateDirectory('/tmp/mb-runtime')) die('revision_key_unavailable');
	let key = privateJson(PATH, 4096);
	if (key == null) {
		let file = open(PATH, 'wxe', 0o600);
		if (file == null) die('revision_key_unavailable');
		key = { secret: nonce() + nonce() };
		let data = sprintf('%J', key), ok = file.write(data) == length(data);
		if (!file.close() || !ok) { unlink(PATH); die('revision_key_unavailable'); }
	}
	if (type(key.secret) != 'string' || match(key.secret, /^[a-f0-9]{64}$/) == null) die('revision_key_unavailable');
	return fingerprint([key.secret, scope, value]);
}
export { opaqueRevision };
