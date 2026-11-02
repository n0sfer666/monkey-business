import { routeIdentity } from '../lib/network-epoch.uc';
import { localAddresses } from '../lib/local-addresses.uc';
import { readfile } from 'fs';
import { loadApplied } from './applied.uc';
import { availabilitySettings } from './availability-settings.uc';
import { listenerOwner } from './engine-listener.uc';
import { isHysteria } from '../generator/hysteria.uc';
import { fingerprint } from './fingerprint.uc';
import { acquireMutation } from './mutation.uc';
import { privateJson } from './private-store.uc';
import { sameContext, initial, fresh } from '../lib/health.uc';
const LIVE = '/sys/fs/cgroup/monkey-business-engines/live';
function networkEpoch() {
	let identity = routeIdentity(readfile('/proc/net/route'), readfile('/proc/net/ipv6_route'),
		localAddresses(readfile('/proc/net/fib_trie')), readfile('/proc/net/if_inet6'));
	for (let name in identity.interfaces) identity.links[name] = [readfile('/sys/class/net/' + name + '/ifindex'),
		readfile('/sys/class/net/' + name + '/carrier_changes'), readfile('/sys/class/net/' + name + '/operstate')];
	return fingerprint(identity);
}
function healthContext(freshCursor) {
	let applied = loadApplied(), method = availabilitySettings(freshCursor).get(), cursor = freshCursor();
	if (applied == null || method.error != null) return null;
	let live = listenerOwner(LIVE, 11800), bridge = null;
	if (isHysteria(applied.config.server)) bridge = listenerOwner(LIVE, 10810);
	return { applied: applied, method: method, live: live,
		context: { boot: trim(readfile('/proc/sys/kernel/random/boot_id')), outbound: applied.generation,
			runtime: fingerprint([applied.epoch, live, bridge]), method: method.revision, network: networkEpoch() },
		missing: live == null || (isHysteria(applied.config.server) && bridge == null),
		enabled: cursor.get('monkey-business', 'global', 'enabled') == '1' };
}
function readHealth(freshCursor) {
	let current = healthContext(freshCursor), health = privateJson('/tmp/mb-runtime/health.json', 65536);
	if (current == null || !current.enabled) return null;
	if (health == null || !sameContext(health.context, current.context)) return initial(current.context);
	return health;
}
function publicHealth(freshCursor) {
	let lock = acquireMutation();
	if (lock == null) return { applying: true, reason: 'applying', https: { state: 'unknown' }, udp: { state: 'unknown' } };
	lock.close();
	let health = readHealth(freshCursor);
	if (health == null) return null;
	let now = +split(readfile('/proc/uptime'), ' ')[0];
	return { https: health.https, udp: health.udp, partial: health.partial, udp_partial: health.udp_partial,
		measured: health.measured, stale: !fresh(health, now), reason: health.reason,
		policy_error: health.policy_error, conntrack: health.conntrack };
}
export { networkEpoch, healthContext, readHealth, publicHealth };
