import { test, assert, assertEq, run } from '../harness.uc';
import { bindingRequest, bindingSuccess, socksDatagram, socksPayload } from '../../src/lib/stun.uc';
const TX = '0123456789ab';
const RESPONSE = '\x01\x01\x00\x0c\x21\x12' + chr(0xa4) + '\x42' + TX + '\x00\x20\x00\x08\x00\x01\x12\x34\x01\x02\x03\x04';
test('STUN validates type, cookie, transaction, total size and mapped attribute bounds', function() {
	assertEq(length(bindingRequest(TX)), 20);
	assert(bindingSuccess(RESPONSE, TX));
	assert(!bindingSuccess(RESPONSE, 'other_transa'));
	assert(!bindingSuccess(RESPONSE + 'x', TX));
	assert(!bindingSuccess(substr(RESPONSE, 0, 25), TX));
	assert(!bindingSuccess('\x01\x01\x00\x00\x21\x12' + chr(0xa4) + '\x42' + TX, TX));
});
test('SOCKS UDP rejects fragments and truncated domain/IPv6 headers', function() {
	let packet = socksDatagram('stun.example.com', 3478, RESPONSE);
	assertEq(socksPayload(packet, 3478), RESPONSE);
	assertEq(socksPayload(packet, 3479), null);
	assertEq(socksPayload('\x00\x00\x01' + substr(packet, 3), 3478), null);
	assertEq(socksPayload('\x00\x00\x00\x04short', 3478), null);
	assertEq(socksPayload('\x00\x00\x00\x03\xffshort', 3478), null);
});
exit(run());
