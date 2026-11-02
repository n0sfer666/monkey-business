// The applied server snapshot deliberately does not consult mutable subscriptions.
import { readfile } from 'fs';
import { atomicPrivate, privateJson, nonce } from './private-store.uc';
import { CONF_DIR } from './paths.uc';

const APPLIED = CONF_DIR + '/applied.json';
function loadApplied(path) {
	let value = privateJson(path || APPLIED, 1048576);
	if (type(value) != 'object' || value.version != 1 || type(value.generation) != 'string' ||
		type(value.config) != 'object' || type(value.config.server) != 'object' ||
		type(value.config.global) != 'object') return null;
	return value;
}
function storeApplied(config, generation, path) {
	let body = sprintf('%J', { version: 1, boot: trim(readfile('/proc/sys/kernel/random/boot_id')),
		generation: generation || nonce(), epoch: nonce(), config: config });
	return length(body) <= 1048576 && atomicPrivate(path || APPLIED, body);
}
export { APPLIED, loadApplied, storeApplied };
