import { unlink } from 'fs';
import { AUTOSWITCH_FILE } from './paths.uc';
import { privateDirectory, privateJson, atomicPrivate } from './private-store.uc';
function loadAutoswitch() {
 let value = privateJson(AUTOSWITCH_FILE, 4096);
 return value != null && type(value.from) == 'string' && type(value.reason) == 'string' ? value : null;
}
function storeAutoswitch(from, reason) {
 if (type(from) != 'string' || length(from) > 64 || type(reason) != 'string' || length(reason) > 32) return false;
 return privateDirectory('/tmp/mb-runtime') && atomicPrivate(AUTOSWITCH_FILE, sprintf('%J', { from: from, reason: reason }));
}
function clearAutoswitch() { unlink(AUTOSWITCH_FILE); }
export { loadAutoswitch, storeAutoswitch, clearAutoswitch };
