import { test, assertEq, run } from '../harness.uc';
import { scope, start, status, page } from '../../src/lib/availability-job.uc';
const SERVERS = [ { tag: 'manual', source: 'manual', disabled: '1' },
	{ tag: 'sub', source: 'subscription', sub: 'group' } ];
test('manual scan includes disabled candidates and rejects excessive scope and identity conflicts', function() {
	assertEq(length(scope(SERVERS, { scope: 'all' }).servers), 2);
	let many = []; for (let i = 0; i < 201; i++) push(many, { tag: '' + i, source: 'manual' });
	assertEq(scope(many, { scope: 'all' }).error, 'scope_too_large');
	assertEq(scope([SERVERS[0], SERVERS[0]], { scope: 'all' }).error, 'identity_conflict');
});
test('status pagination cannot expose worker secrets or use paths as IDs', function() {
	let job = start('test_job', [{ server_ref: { source: 'manual', tag: 'manual' }, name: 'manual',
		state: 'checking', password: 'synthetic', url: 'https://private.example/path' }], 1, 'boot');
	let result = status(job, { job_id: 'test_job', offset: 0, limit: 50 }, 2, 'boot');
	assertEq(result.rows[0].password, null); assertEq(result.rows[0].url, null);
	assertEq(page({ job_id: '../file', offset: 0, limit: 1 }).error, 'invalid_page');
	assertEq(page({ job_id: 'job', offset: 0, limit: 51 }).error, 'invalid_page');
	assertEq(page({ job_id: 'job', offset: '0', limit: 1 }).error, 'invalid_page');
	assertEq(status(job, { job_id: 'test_job', offset: 0, limit: 1 }, 242, 'boot').state, 'incomplete');
	assertEq(status(job, { job_id: 'test_job', offset: 0, limit: 1 }, 2, 'other').error, 'unknown_job');
});
exit(run());
