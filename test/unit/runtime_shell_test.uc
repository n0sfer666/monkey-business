import { test, assertEq, run } from "../harness.uc";
import { shq, stripExit, noSelfMatch, firstLine, xrayError } from "../../src/runtime/shell.uc";

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

test("xrayError keeps the last two segments of xray's Failed to start line", function() {
	let banner = "Xray 25.1.1 (Xray, Penetrates Everything.)\nA unified platform for anti-censorship.\n";
	assertEq(xrayError(banner + "Failed to start: main: failed to load config files: [/tmp/t.json] > infra/conf: failed to build routing configuration > infra/conf: failed to load geosite: NOSUCH > infra/conf: code not found in geosite.dat: NOSUCH\n"),
		"xray rejected the config: failed to load geosite: NOSUCH — code not found in geosite.dat: NOSUCH");
	assertEq(xrayError(banner + "Failed to start: main: failed to load config files: [/tmp/t.json] > infra/conf: invalid IP: 10.0.0.0/33 > infra/conf: invalid network mask for router: 33"),
		"xray rejected the config: invalid IP: 10.0.0.0/33 — invalid network mask for router: 33");
	assertEq(xrayError("Failed to start: main: failed to load config files: [/tmp/t.json] > invalid character 'b' looking for beginning of object key string"),
		"xray rejected the config: invalid character 'b' looking for beginning of object key string");
	assertEq(xrayError(banner), "");
	assertEq(xrayError("sh: xray: not found\nMB_EXIT:127\n"), "sh: xray: not found");
	assertEq(xrayError(banner + "panic: boom\n"), "panic: boom");
	assertEq(xrayError(""), "");
	assertEq(xrayError(null), "");
});

exit(run());
