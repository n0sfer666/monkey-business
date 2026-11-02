// Public job operations never return definitions containing credentials or target URLs.
import { readfile } from 'fs';
import { networkEpoch } from './health-context.uc';
import { availabilitySettings } from './availability-settings.uc';
import { enqueue, jobStatus, cancelJob, boot } from './jobs.uc';
import { loadServers, loadSection } from './uci.uc';
import { readJob } from './jobs.uc';
import { monotonic } from './routing-v2.uc';
import { resolveRef, fresh, complete } from '../lib/availability.uc';
import { outboundPayload } from '../lib/outbound.uc';
import { CONFIG } from './paths.uc';
import { fingerprint } from './fingerprint.uc';
function availabilityApi(freshCursor) {
	let settings = availabilitySettings(freshCursor);
	function start(args) {
		let method = settings.get();
		if (method.error != null) return method;
		let cursor = freshCursor();
		method.dns = loadSection(cursor, 'dns');
		return enqueue(loadServers(cursor), args, method, networkEpoch());
	}
	function status(args) {
		let result = jobStatus(args);
		if (result.error != null) return result;
		let job = readJob(args.job_id), servers = loadServers(freshCursor()), method = settings.get();
		let network = networkEpoch(), now = monotonic();
		for (let i = 0; i < length(result.rows); i++) {
			let public_ = result.rows[i], row = job.rows[args.offset + i], found = resolveRef(servers, public_.server_ref);
			public_.complete = complete(row);
			public_.fresh = public_.complete && found.error == null && method.error == null && fresh(row, {
				fingerprint: fingerprint(outboundPayload(found.server)), method: method.revision,
				network: network, boot: boot() }, now);
			public_.age = row.base_finished != null ? max(0, int(now - row.base_finished)) : null;
		}
		return result;
	}
	return { start: start, status: status, cancel: cancelJob,
		settingsGet: settings.get, settingsApply: settings.apply };
}
export { availabilityApi };
