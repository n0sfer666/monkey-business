// Stable transport identity excludes UCI order/editor metadata and display labels.
function outboundPayload(server) {
	let result = {};
	for (let field in ['protocol', 'address', 'port', 'uuid', 'password', 'encryption', 'flow',
		'security', 'sni', 'fingerprint', 'alpn', 'transport', 'reality', 'obfs', 'pin_sha256', 'insecure', 'mport'])
		result[field] = server[field];
	return result;
}
export { outboundPayload };
