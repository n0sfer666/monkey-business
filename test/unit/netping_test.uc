import { test, assert, assertEq, run } from "../harness.uc";
import { shq } from "../../src/runtime/shell.uc";
import { netRuntime } from "../../src/runtime/net.uc";

function fakeNet(out) {
	let calls = [];
	let net = netRuntime({
		shq: shq,
		runCapture: function(cmd) { push(calls, cmd); return { out: out }; },
	}, null, null);
	return { net: net, calls: calls };
}

function count(s, part) {
	return length(split(s, part)) - 1;
}

test("tcpPings runs one curl per server in the background and waits for all", function() {
	let f = fakeNet("");
	f.net.tcpPings([ { address: "1.2.3.4", port: "443" }, { address: "2001:db8::1", port: 8443 } ], 1000);
	assertEq(length(f.calls), 1);
	let cmd = f.calls[0];
	assertEq(count(cmd, "curl -gs "), 2);
	assertEq(count(cmd, ") & "), 2);
	assert(index(cmd, "--connect-timeout 2 --max-time 2 ") >= 0, "таймаут от лимита");
	assert(index(cmd, "http://'1.2.3.4':443 ") >= 0, "IPv4 в кавычках");
	assert(index(cmd, "http://'[2001:db8::1]':8443 ") >= 0, "IPv6 в скобках");
	assert(index(cmd, 'printf "1 %d') >= 0, "индекс строки");
	assertEq(substr(cmd, -4), "wait");
});

test("tcpPings quotes a hostile address", function() {
	let f = fakeNet("");
	f.net.tcpPings([ { address: "x';reboot;'", port: "1; reboot" } ], 1000);
	assert(index(f.calls[0], "http://'x'\\'';reboot;'\\''':1 ") >= 0, "адрес в shq, порт через int");
});

test("tcpPings waits between batches of 16", function() {
	let list = [];
	for (let i = 0; i < 17; i++)
		push(list, { address: "10.0.0." + i, port: 443 });
	let f = fakeNet("");
	f.net.tcpPings(list, 1000);
	assertEq(count(f.calls[0], "wait; "), 1);
	assert(index(f.calls[0], "& wait; (curl") >= 0, "пачка закрывается wait");
});

test("tcpPings maps results by index and drops garbage", function() {
	let f = fakeNet("2 40\n0 5\njunk\n1 0\n7 10\n-1 3\nMB_EXIT:0");
	let s = { address: "1.1.1.1", port: 443 };
	assertEq(f.net.tcpPings([ s, s, s, s ], 1000), [ 5, null, 40, null ]);
});

test("tcpPings on an empty list runs nothing", function() {
	let f = fakeNet("");
	assertEq(f.net.tcpPings([], 1000), []);
	assertEq(f.calls, []);
});

exit(run());
