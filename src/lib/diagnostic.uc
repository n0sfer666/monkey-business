// Reserved pool shared by generator, guard, worker and observer.
const HEALTH_PORT = 11800;
const PROBE_BASE = 11801;
const PROBE_LIMIT = 12000;
const BRIDGE_BASE = 12001;
const POOL_END = 12263;
function diagnosticPort(port) {
	return type(port) == 'int' && port >= HEALTH_PORT && port <= POOL_END;
}
function diagnosticCredentials(value) {
	return type(value) == 'object' && type(value.user) == 'string' && type(value.pass) == 'string' &&
		match(value.user, /^[a-f0-9]{32}$/) != null && match(value.pass, /^[a-f0-9]{32}$/) != null;
}
export { HEALTH_PORT, PROBE_BASE, PROBE_LIMIT, BRIDGE_BASE, POOL_END, diagnosticPort, diagnosticCredentials };
