// SOCKS control stays open; explicit UDP source pin prevents first-packet theft.
import * as socket from 'socket';
import { readfile } from 'fs';
import { ownsListener } from './listener.uc';
import { bindingRequest, bindingSuccess, socksDatagram, socksPayload, uint16 } from '../lib/stun.uc';
import { diagnosticCredentials, diagnosticPort } from '../lib/diagnostic.uc';

const TARGETS = [ { host: 'stun.cloudflare.com', port: 3478 }, { host: 'global.stun.twilio.com', port: 3478 } ];
function now() { return +split(readfile('/proc/uptime'), ' ')[0]; }
function ready(handle, events, deadline) {
	let remaining = int((deadline - now()) * 1000);
	if (remaining <= 0) return false;
	let result = socket.poll(remaining, [handle, events]);
	return result != null && length(result) && (result[0][1] & events) != 0;
}
function sendAll(handle, data, deadline) {
	let offset = 0;
	while (offset < length(data)) {
		if (!ready(handle, socket.POLLOUT, deadline)) die('control_timeout');
		let sent = handle.send(substr(data, offset), socket.MSG_DONTWAIT | socket.MSG_NOSIGNAL);
		if (sent == null || sent <= 0) die('control_send_failed');
		offset += sent;
	}
}
function exact(handle, count, deadline) {
	let data = '';
	while (length(data) < count) {
		if (!ready(handle, socket.POLLIN, deadline)) die('control_timeout');
		let part = handle.recv(count - length(data), socket.MSG_DONTWAIT);
		if (part == null || !length(part)) die('control_closed');
		data += part;
	}
	return data;
}
function probeUdp(diagnostic, targets) {
	let control = null, udp = null;
	let result;
	let deadline = now() + 2;
	try {
		if (type(diagnostic) != 'object' || !diagnosticPort(diagnostic.port) ||
			!diagnosticCredentials(diagnostic.credentials) ||
			!ownsListener(diagnostic.pid, diagnostic.identity, diagnostic.port)) die('listener_identity_failed');
		targets = targets || TARGETS;
		if (length(targets) != 2) die('invalid_targets');
		udp = socket.create(socket.AF_INET, socket.SOCK_DGRAM | socket.SOCK_NONBLOCK | socket.SOCK_CLOEXEC, 0);
		if (udp == null || !udp.bind({ address: '127.0.0.1', port: 0 })) die('udp_bind_failed');
		let source = udp.sockname();
		control = socket.connect({ address: '127.0.0.1', port: diagnostic.port }, null,
			{ socktype: socket.SOCK_STREAM }, max(1, int((deadline - now()) * 1000)));
		if (control == null) die('control_connect_failed');
		sendAll(control, '\x05\x01\x02', deadline);
		if (exact(control, 2, deadline) != '\x05\x02') die('authentication_failed');
		let credentials = diagnostic.credentials;
		sendAll(control, '\x01' + chr(length(credentials.user)) + credentials.user +
			chr(length(credentials.pass)) + credentials.pass, deadline);
		if (exact(control, 2, deadline) != '\x01\x00') die('authentication_failed');
		sendAll(control, '\x05\x03\x00\x01\x7f\x00\x00\x01' + chr(source.port >> 8) + chr(source.port & 255), deadline);
		let reply = exact(control, 10, deadline);
		if (substr(reply, 0, 8) != '\x05\x00\x00\x01\x7f\x00\x00\x01') die('unsafe_udp_relay');
		// The SOCKS TCP listener is identity-checked; loopback relay is source-pinned
		// from creation. Kernel connected UDP additionally filters foreign relays.
		if (!udp.connect({ address: '127.0.0.1', port: uint16(reply, 8) })) die('udp_connect_failed');
		let transactions = [], rows = [];
		for (let target in targets) {
			let transaction = readfile('/dev/urandom', 12);
			if (transaction == null || length(transaction) != 12) die('random_source_failed');
			push(transactions, transaction);
			let packet = socksDatagram(target.host, target.port, bindingRequest(transaction));
			if (udp.send(packet, socket.MSG_DONTWAIT | socket.MSG_NOSIGNAL) != length(packet)) die('udp_send_failed');
			push(rows, { state: 'failure' });
		}
		let successes = 0;
		while (successes < 2 && ready(udp, socket.POLLIN, deadline)) {
			let packet = udp.recv(8192, socket.MSG_DONTWAIT);
			if (packet == null) die('udp_receive_failed');
			for (let i = 0; i < 2; i++) {
				let payload = socksPayload(packet, targets[i].port);
				if (rows[i].state != 'success' && payload != null && bindingSuccess(payload, transactions[i])) {
					rows[i] = { state: 'success' }; successes++;
				}
			}
		}
		result = { state: successes ? 'success' : 'failure', partial: successes == 1, targets: rows };
	} catch (e) {
		// Diagnostic errors never become a synthetic network failure.
		result = { state: 'unknown', reason: 'udp_method_error', targets: [{ state: 'unknown' }, { state: 'unknown' }] };
	}
	if (udp != null) udp.close();
	if (control != null) control.close();
	return result;
}
export { probeUdp, TARGETS };
