const COOKIE = chr(0x21) + chr(0x12) + chr(0xa4) + chr(0x42);
function uint16(data, offset) {
	return (ord(data, offset) << 8) | ord(data, offset + 1);
}
function bindingRequest(transaction) {
	if (type(transaction) != 'string' || length(transaction) != 12) die('invalid_stun_transaction');
	return '\x00\x01\x00\x00' + COOKIE + transaction;
}
function bindingSuccess(data, transaction) {
	if (type(data) != 'string' || length(data) < 20 || length(data) > 4096 ||
		uint16(data, 0) != 0x0101 || substr(data, 4, 4) != COOKIE ||
		substr(data, 8, 12) != transaction) return false;
	let size = uint16(data, 2);
	if (size % 4 || size + 20 != length(data)) return false;
	let mapped = false;
	for (let offset = 20; offset < length(data);) {
		if (offset + 4 > length(data)) return false;
		let type_ = uint16(data, offset), length_ = uint16(data, offset + 2);
		offset += 4;
		if (offset + length_ > length(data)) return false;
		if (type_ == 1 || type_ == 0x20) {
			if (length_ < 4 || ord(data, offset) != 0) return false;
			let family = ord(data, offset + 1);
			if ((family == 1 && length_ != 8) || (family == 2 && length_ != 20) ||
				(family != 1 && family != 2)) return false;
			mapped = true;
		}
		offset += (length_ + 3) & ~3;
		if (offset > length(data)) return false;
	}
	return mapped;
}
function socksDatagram(host, port, payload) {
	if (type(host) != 'string' || length(host) > 253 || match(host, /^[a-z0-9.-]+$/i) == null ||
		type(port) != 'int' || port < 1 || port > 65535) die('invalid_udp_target');
	return '\x00\x00\x00\x03' + chr(length(host)) + host + chr(port >> 8) + chr(port & 255) + payload;
}
function socksPayload(packet, port) {
	if (length(packet) < 7 || substr(packet, 0, 3) != '\x00\x00\x00') return null;
	let kind = ord(packet, 3), offset;
	if (kind == 1) offset = 8;
	else if (kind == 4) offset = 20;
	else if (kind == 3) offset = 5 + ord(packet, 4);
	else return null;
	if (offset + 2 > length(packet) || uint16(packet, offset) != port) return null;
	return substr(packet, offset + 2);
}
export { uint16, bindingRequest, bindingSuccess, socksDatagram, socksPayload };
