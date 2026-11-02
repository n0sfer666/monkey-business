import { test, assert, assertEq, run } from '../harness.uc';
import { mkdir, lstat, symlink, readfile, unlink, rmdir } from 'fs';
import { privateDirectory, nonce, atomicPrivate, privateJson } from '../../src/runtime/private-store.uc';

const DIR = '/tmp/mb-store-test-' + nonce();

test('private store creates secrets with 0600 and atomically replaces symlink', function() {
	assert(privateDirectory(DIR));
	assertEq(lstat(DIR).mode & 0o777, 0o700);
	assert(atomicPrivate(DIR + '/value', '{"test":true}'));
	assertEq(lstat(DIR + '/value').mode & 0o777, 0o600);
	assertEq(privateJson(DIR + '/value', 100), { test: true });
	assertEq(privateJson(DIR + '/value', 2), null);
	assert(symlink(DIR + '/value', DIR + '/alias'));
	assertEq(privateJson(DIR + '/alias', 100), null);
	assert(atomicPrivate(DIR + '/alias', '{"replaced":true}'));
	assertEq(readfile(DIR + '/value'), '{"test":true}');
	assertEq(privateJson(DIR + '/alias', 100), { replaced: true });
});

test('private directory rejects foreign permissive directory and symlink', function() {
	assert(!privateDirectory('/tmp'));
	assert(symlink(DIR, DIR + '-link'));
	assert(!privateDirectory(DIR + '-link'));
	unlink(DIR + '-link');
});

let result = run();
unlink(DIR + '/value'); unlink(DIR + '/alias'); rmdir(DIR);
exit(result);
