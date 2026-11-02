// Retained only for old internal consumers; legacy public ping RPCs are deprecated.
import { PING_STATE } from './paths.uc';
import { privateDirectory, privateJson, atomicPrivate } from './private-store.uc';
function loadPings() { return privateJson(PING_STATE, 262144) || {}; }
function storePings(pings) {
 let body = sprintf('%J', pings);
 return length(body) <= 262144 && privateDirectory('/tmp/mb-runtime') && atomicPrivate(PING_STATE, body);
}
export { loadPings, storePings };
