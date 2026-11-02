// Node cache is independent of the four retained job histories. An unfinished
// newer scan can neither replace a completed node nor evict it by job rotation.
import { readfile } from 'fs';
import { complete, refKey } from '../lib/availability.uc';
import { privateDirectory, privateJson, atomicPrivate } from './private-store.uc';
const FILE = '/tmp/mb-runtime/availability-records.json';
function currentBoot() { return trim(readfile('/proc/sys/kernel/random/boot_id')); }
function now() { return +split(readfile('/proc/uptime'), ' ')[0]; }
function mergeRecord(records, row, current, boot) {
 let latest = {};
 for (let item in [...(records || []), ...(row != null ? [row] : [])]) {
  let key = refKey(item.server_ref);
  if (key == null || !complete(item) || item.boot != boot || current < item.base_finished || current - item.base_finished > 600) continue;
  if (latest[key] == null || latest[key].base_finished <= item.base_finished) latest[key] = item;
 }
 return slice(sort(values(latest), function(a, b) { return b.base_finished - a.base_finished; }), 0, 500);
}
function readRecords() { return mergeRecord(privateJson(FILE, 4194304) || [], null, now(), currentBoot()); }
function rememberRecord(row) {
 if (!complete(row)) return true;
 if (!privateDirectory('/tmp/mb-runtime')) return false;
 let body = sprintf('%J', mergeRecord(readRecords(), row, now(), currentBoot()));
 return length(body) <= 4194304 && atomicPrivate(FILE, body);
}
export { mergeRecord, readRecords, rememberRecord };
