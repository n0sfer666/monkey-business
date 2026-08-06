// Запуск команд из rpcd-плагина и обвязка вокруг него. Всё, кроме самого popen, — чистые функции:
// именно на них ловились самые дорогие дефекты (самоматч pgrep, утечка служебного маркера в UI),
// поэтому они лежат отдельно и покрыты host-тестами (test/unit/runtime_shell_test.uc).

import { popen } from 'fs';

// POSIX single-quote экранирование: ' -> '\'' (закрыть кавычку, экранированный ', снова открыть).
// Раньше кавычки УДАЛЯЛИСЬ -> молчаливая порча URL/значений с апострофом.
function shq(s) {
	return "'" + replace(s != null ? s : '', "'", "'\\''") + "'";
}

function runCapture(cmd) {
	let p = popen(cmd + '; echo "MB_EXIT:$?"');
	let out = p ? p.read('all') : '';
	if (p) p.close();
	return { out: (out != null) ? out : '', ok: index(out != null ? out : '', 'MB_EXIT:0') >= 0 };
}

// Служебный маркер runCapture — не часть вывода команды. Без вычистки команда, ничего не
// напечатавшая, отдавала наружу буфер из одной строки "MB_EXIT:0", и он утекал в UI как
// «последнее событие» / detail ошибки.
function stripExit(s) {
	let keep = [];
	for (let l in split((s != null) ? s : '', '\n'))
		if (index(l, 'MB_EXIT:') != 0)
			push(keep, l);
	return join('\n', keep);
}

// pgrep/pkill -f матчат и промежуточный `sh -c <вся команда>` из popen(): паттерн лежит в его же
// cmdline. Из-за этого pkill в probeServer убивал СОБСТВЕННЫЙ шелл ещё до старта xray (проба
// всегда падала -> «no working failover server»), а pgrep рапортовал «сервис жив» всегда.
// `[x]ray…` — регексп, который матчит боевой процесс, но не текст самой команды.
function noSelfMatch(cmdline) {
	return '[' + substr(cmdline, 0, 1) + ']' + substr(cmdline, 1);
}

function firstLine(s) {
	let parts = split(trim(s != null ? s : ''), "\n");
	return length(parts) > 0 ? trim(parts[0]) : '';
}

export { shq, runCapture, stripExit, noSelfMatch, firstLine };
