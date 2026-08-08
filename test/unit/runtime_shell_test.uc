import { test, assertEq, run } from "../harness.uc";
import { shq, stripExit, noSelfMatch, firstLine } from "../../src/runtime/shell.uc";

test("shq wraps a plain value in single quotes", function() {
	assertEq(shq("https://sub.example/x?token=abc"), "'https://sub.example/x?token=abc'");
});

// Регрессия: раньше апостроф УДАЛЯЛСЯ -> URL подписки тихо портился.
test("shq escapes an apostrophe instead of dropping it", function() {
	assertEq(shq("it's"), "'it'\\''s'");
});

test("shq handles null as an empty quoted string", function() {
	assertEq(shq(null), "''");
});

// Регрессия: команда без вывода отдавала наружу буфер "MB_EXIT:0", и он утекал в UI
// как «последнее событие».
test("stripExit removes the marker line", function() {
	assertEq(stripExit("MB_EXIT:0"), "");
	assertEq(stripExit("hello\nMB_EXIT:0"), "hello");
	assertEq(stripExit("MB_EXIT:1\n"), "");
});

// Маркер вычищается только когда он НАЧИНАЕТ строку: строка вывода, где 'MB_EXIT:' попался
// в середине, — это данные команды.
test("stripExit keeps a line that merely mentions the marker", function() {
	assertEq(stripExit("prefix MB_EXIT:0"), "prefix MB_EXIT:0");
});

// Регрессия: pkill -f матчил собственный `sh -c` из popen() -> проба failover всегда падала.
test("noSelfMatch brackets the first character", function() {
	assertEq(noSelfMatch("xray run -c /tmp/mb-probe.json"), "[x]ray run -c /tmp/mb-probe.json");
});

test("firstLine trims and takes only the first line", function() {
	assertEq(firstLine("  first \n second \n"), "first");
	assertEq(firstLine(""), "");
	assertEq(firstLine(null), "");
});

exit(run());
