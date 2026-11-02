import { test, assert, run } from '../harness.uc';
import { acceptedOwner } from '../../src/runtime/engine-listener.uc';
test('unbound candidate present before rollback cannot become its restored owner', function() {
 let candidate = { pid: 20, identity: '200' }, original = { pid: 10, identity: '100' };
 assert(!acceptedOwner(candidate, [candidate], original));
 assert(acceptedOwner(original, [candidate, original], original));
 assert(acceptedOwner({ pid: 30, identity: '300' }, [candidate, original], original));
 assert(!acceptedOwner(null, [candidate], null));
});
exit(run());
