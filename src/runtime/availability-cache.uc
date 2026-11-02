import { boot } from './jobs.uc';
import { readRecords } from './availability-records.uc';
import { refKey, serverRef, fresh } from '../lib/availability.uc';
import { outboundPayload } from '../lib/outbound.uc';
import { fingerprint } from './fingerprint.uc';
import { monotonic } from './routing-v2.uc';
import { networkEpoch } from './health-context.uc';
function availabilityCache(servers, method) {
	let rows = {}, result = {}, now = monotonic(), network = networkEpoch(), boot_ = boot();
	for (let row in readRecords()) rows[refKey(row.server_ref)] = row;
	for (let server in servers) {
		let key = refKey(serverRef(server)), row = rows[key];
		if (row == null) continue;
		let valid = fresh(row, { fingerprint: fingerprint(outboundPayload(server)), method: method.revision,
			network: network, boot: boot_ }, now);
		result[key] = { state: valid ? row.state : 'unknown', previous_state: row.state, fresh: valid,
			age: max(0, int(now - row.base_finished)), latency_ms: row.latency_ms, successes: row.successes,
			attempts: row.attempts, udp: row.udp, extra_failed: row.extra_failed };
	}
	return result;
}
export { availabilityCache };
