import { readfile, unlink, lstat } from 'fs';
import { privateDirectory, atomicPrivate, nonce } from './private-store.uc';
import { ownsListener } from './listener.uc';
import { curlConfig, normalizeTarget } from '../lib/availability-settings.uc';
import { diagnosticPort, diagnosticCredentials } from '../lib/diagnostic.uc';

function probeHttps(sh, diagnostic, target, directory) {
	let checked = normalizeTarget(target);
	if (checked.error != null) return { state: 'config_error', reason: 'invalid_target' };
	if (!diagnosticPort(diagnostic.port) || !diagnosticCredentials(diagnostic.credentials) ||
		!ownsListener(diagnostic.pid, diagnostic.identity, diagnostic.port))
		return { state: 'engine_error', reason: 'listener_identity_failed' };
	if (!privateDirectory(directory)) return { state: 'engine_error', reason: 'unsafe_probe_directory' };
	let base = directory + '/https-' + nonce(), result;
	try {
		if (!atomicPrivate(base + '.conf', curlConfig(checked.target, diagnostic, base + '.body')))
			die('config_write_failed');
		let command = sh.runCapture('umask 077; timeout 7 curl --disable --config ' + base + '.conf 2>/dev/null');
		let output = match(trim(sh.stripExit(command.out)), /^([0-9]{3}) ([0-9]+(\.[0-9]+)?)$/);
		let body = lstat(base + '.body');
		if (command.ok && output != null && int(output[1]) == checked.target.expected_status &&
			body != null && body.type == 'file' && body.size <= 4096)
			result = { state: 'success', latency_ms: int((+output[2]) * 1000) };
		else if (index([2, 3, 4, 23, 26, 27, 43, 48, 58, 59, 77], command.code) >= 0)
			result = { state: 'engine_error', reason: 'https_dependency_error' };
		else if (output != null) result = { state: 'failure', reason: 'https_request_failed' };
		else result = { state: 'engine_error', reason: 'https_method_failed' };
	} catch (e) { result = { state: 'engine_error', reason: 'https_method_failed' }; }
	unlink(base + '.conf'); unlink(base + '.body');
	return result;
}
export { probeHttps };
