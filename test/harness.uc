// Минимальный test-харнесс для ucode.
// Использование в тест-файле:
//   import { test, assertEq, run } from "../harness.uc";
//   test("name", function() { assertEq(actual, expected); });
//   exit(run());

let _tests = [];
let _pass = 0;
let _fail = 0;
let _failures = [];

function _def(value, fallback) {
	return (value != null) ? value : fallback;
}

function test(name, fn) {
	push(_tests, { name: name, fn: fn });
}

// Глубокое сравнение через каноничную JSON-сериализацию.
function eq(a, b) {
	return sprintf("%J", a) == sprintf("%J", b);
}

function assert(cond, msg) {
	if (!cond)
		die(_def(msg, "assertion failed"));
}

function assertEq(actual, expected, msg) {
	if (!eq(actual, expected))
		die(sprintf("%s\n  expected: %.J\n  actual:   %.J",
			_def(msg, "assertEq failed"), expected, actual));
}

function assertThrows(fn, msg) {
	let threw = false;
	try {
		fn();
	} catch (e) {
		threw = true;
	}
	if (!threw)
		die(_def(msg, "expected function to throw"));
}

function run() {
	for (let t in _tests) {
		try {
			t.fn();
			_pass++;
			printf("  ok    %s\n", t.name);
		} catch (e) {
			_fail++;
			push(_failures, { name: t.name, msg: _def(e.message, e) });
			printf("  FAIL  %s\n", t.name);
		}
	}
	printf("\n%d passed, %d failed\n", _pass, _fail);
	for (let f in _failures)
		printf("\n--- FAIL: %s ---\n%s\n", f.name, f.msg);
	return (_fail == 0) ? 0 : 1;
}

export { test, assert, assertEq, assertThrows, eq, run };
