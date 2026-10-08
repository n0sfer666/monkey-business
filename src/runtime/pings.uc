import { readfile, writefile, rename, unlink } from 'fs';
import { PING_STATE } from './paths.uc';
import { safeJson } from '../lib/val.uc';

function loadPings() {
	let raw = readfile(PING_STATE);
	let j = (raw != null) ? safeJson(raw) : null;
	return (type(j) == 'object') ? j : {};
}

function storePings(pings) {
	let body = sprintf('%J', pings);
	let tmp = PING_STATE + '.new';
	if (writefile(tmp, body) != length(body) || !rename(tmp, PING_STATE))
		unlink(tmp);
}

export { loadPings, storePings };
