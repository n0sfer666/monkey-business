import { test, assert, assertEq, assertThrows, eq, run } from "../harness.uc";

test("eq deep-compares structures", function() {
	assert(eq([1, 2, { a: 3 }], [1, 2, { a: 3 }]), "equal structures");
	assert(!eq([1, 2], [1, 3]), "unequal structures");
});

test("assertEq passes on equal values", function() {
	assertEq(2 + 2, 4);
	assertEq({ x: [1, 2] }, { x: [1, 2] });
});

test("assertThrows catches die()", function() {
	assertThrows(function() { die("boom"); });
});

exit(run());
