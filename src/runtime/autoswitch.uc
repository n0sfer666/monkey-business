import { readfile, writefile, rename, unlink } from 'fs';
import { AUTOSWITCH_FILE } from './paths.uc';

function loadAutoswitch() {
	let raw = readfile(AUTOSWITCH_FILE);
	let m = (raw != null) ? match(trim(raw), /^([A-Za-z0-9_-]+) ([a-z]+)$/) : null;
	return (m != null) ? { from: m[1], reason: m[2] } : null;
}

function storeAutoswitch(from, reason) {
	let body = from + ' ' + reason + '\n';
	let tmp = AUTOSWITCH_FILE + '.new';
	if (writefile(tmp, body) != length(body) || !rename(tmp, AUTOSWITCH_FILE))
		unlink(tmp);
}

function clearAutoswitch() {
	unlink(AUTOSWITCH_FILE);
}

export { loadAutoswitch, storeAutoswitch, clearAutoswitch };
