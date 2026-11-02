import { test, assert, assertEq, run } from '../harness.uc';
import { readfile, unlink, rmdir } from 'fs';
import * as socket from 'socket';
import { privateDirectory, nonce } from '../../src/runtime/private-store.uc';
import { spawnOwned, finished, collect, stopOwned } from '../../src/runtime/owned-process.uc';
const DIR = '/tmp/mb-owned-' + nonce();
assert(privateDirectory(DIR));
test('owned child returns real exit status and reaps once', function() {
	let child = spawnOwned(['sh', '-c', 'printf synthetic; exit 7'], DIR, 2);
	for (let i = 0; i < 100 && !finished(child); i++) socket.poll(10);
	assert(finished(child));
	assertEq(collect(child), { output: 'synthetic', code: 7 });
	assert(stopOwned(child));
});
test('cancellation stops only the recorded process group', function() {
	let child = spawnOwned(['sh', '-c', 'sleep 30'], DIR, 35);
	assert(child.error == null);
	assert(stopOwned(child));
	assert(finished(child));
	assertEq(readfile('/proc/' + child.pid + '/stat'), null);
});
test('a crashed leader cannot leave a background descendant running', function() {
	let child = spawnOwned(['sh', '-c', 'sleep 30 & exit 9'], DIR, 35);
	for (let i = 0; i < 100 && !finished(child); i++) socket.poll(10);
	assert(finished(child));
	assertEq(collect(child).code, 9);
	assert(stopOwned(child));
});
let code = run();
unlink(DIR + '/unused'); rmdir(DIR);
exit(code);
