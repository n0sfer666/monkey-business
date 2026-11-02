const test = require('node:test');
const assert = require('node:assert/strict');
const { load } = require('./luci.js');
const model = load('view.monkey-business.model.routingdraft');

const initial = { revision: 'r1', candidate: { mode: 'global', region: 'ru', corporate_rules: [] } };

test('routing draft survives polls and retries reuse the same request body', () => {
  const draft = model.create(initial);
  const candidate = draft.candidate();

  candidate.region = 'other';
  draft.replace(candidate);
  const first = draft.payload('request_00000001');

  draft.observe({ ...initial, revision: 'r2' });
  assert.equal(draft.candidate().region, 'other');
  assert.equal(draft.revision(), 'r1');
  assert.deepEqual(draft.payload('request_00000002'), first);
  draft.accept({ revision: 'r3', candidate });
  assert.equal(draft.dirty(), false);
});
test('a clean draft follows applied changes without referencing UCI staging', () => {
  const draft = model.create(initial);

  draft.observe({ revision: 'r2', candidate: { ...initial.candidate, region: 'cn' } });
  assert.equal(draft.candidate().region, 'cn');
  assert.equal(draft.revision(), 'r2');
});
