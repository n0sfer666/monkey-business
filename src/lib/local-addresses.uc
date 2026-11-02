// Linux's local FIB contains interface IPv4 addresses, including secondary addresses.
// Parsing it keeps read-only validation free of child processes and network requests.
function localAddresses(fib) {
	let result = [], previous = null;
	for (let line in split(fib || '', '\n')) {
		let address = match(line, /[|+]-- ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/);
		if (address != null) previous = address[1];
		if (previous != null && index(line, '/32 host LOCAL') >= 0) {
			if (index(result, previous) < 0) push(result, previous);
			previous = null;
		}
	}
	return result;
}
export { localAddresses };
