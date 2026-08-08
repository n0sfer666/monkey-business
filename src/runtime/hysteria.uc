// Device-side обвязка hysteria-клиента для rpcd: файл конфига, наличие бинаря, установка, эфемерная
// проба кандидата. Живёт отдельно от плагина rpcd, чтобы тот не рос ещё на одну ответственность;
// чистая логика (что писать в конфиг) — в generator/hysteria.uc.
//
// hysteriaRuntime(run) -> { installed, apply, status, install, probeStart, probeStop, PROBE_SOCKS }
// run — runCapture плагина: (cmd) -> { out, ok }.
'use strict';

import { writefile, stat, readfile } from 'fs';
import { hysteriaConfigJson } from '../generator/hysteria.uc';
import { safeJson } from '../lib/val.uc';
import { stripExit } from './shell.uc';

const BIN = '/usr/bin/hysteria';
const CONF_DIR = '/etc/monkey-business';
const CONF = CONF_DIR + '/hysteria.json';
const SCRIPT = '/usr/share/monkey-business/hysteria.sh';
// Проба кандидата не должна трогать боевой 10810: пока идёт failover, действующий туннель обязан
// продолжать работать.
const PROBE_CONF = '/tmp/mb-hy-probe.json';
const PROBE_SOCKS = 10811;

// pkill -f матчит и собственный `sh -c` из popen (см. noSelfMatch в плагине) — тот же приём.
const PROBE_MATCH = "'[m]b-hy-probe.json'";

function firstLine(s) {
	let parts = split(trim((s != null) ? s : ''), '\n');
	return length(parts) > 0 ? trim(parts[0]) : '';
}

// «Установлен» обязано значить ровно то же, что проверяет init перед объявлением инстанса ([ -x ]),
// иначе существующий, но неисполняемый бинарь (оборванная установка, восстановление из бэкапа)
// прошёл бы сюда: конфиг записан, xray перезагружен аутбаундом в socks 10810, инстанс не объявлен —
// и весь трафик упирается в закрытый порт при поднятом kill-switch. root исполняет файл, если
// выставлен ЛЮБОЙ бит exec — так же, как это видит [ -x ] в init-скрипте.
function installed() {
	let st = stat(BIN);
	if (st == null || st.size == 0 || st.perm == null)
		return false;
	return st.perm.user_exec == true || st.perm.group_exec == true || st.perm.other_exec == true;
}

// Конфиг держит пароль аутентификации, поэтому 0600 ставится на ПУСТОЙ временный файл до записи:
// writefile создал бы его по umask (0644), и между записью и chmod пароль полежал бы читаемым всем
// в общедоступном каталоге. writefile существующий файл усекает, режим при этом сохраняется.
function writeConf(path, jsonStr) {
	let tmp = path + '.new';
	system('rm -f ' + tmp + '; : > ' + tmp + '; chmod 600 ' + tmp);
	if (writefile(tmp, jsonStr) != length(jsonStr)) {
		system('rm -f ' + tmp);
		return 'failed to write the hysteria config (disk full?)';
	}
	if (system('mv ' + tmp + ' ' + path) != 0) {
		system('rm -f ' + tmp);
		return 'failed to install the hysteria config';
	}
	return null;
}

function hysteriaRuntime(run) {
	return {
		PROBE_SOCKS: PROBE_SOCKS,
		installed: installed,
		// jsonStr == null -> сервер не hysteria: конфиг снимается, init перестаёт поднимать инстанс.
		apply: function(jsonStr) {
			if (jsonStr == null) {
				system('rm -f ' + CONF);
				return null;
			}
			if (readfile(CONF) == jsonStr)
				return null;
			system('mkdir -p ' + CONF_DIR);
			return writeConf(CONF, jsonStr);
		},
		// Конфиг на месте = активный сервер hysteria, и без живого клиента туннеля нет, сколько бы
		// xray ни жил. Тот же учёт делает watchdog (hy_active/hy_pids в recovery.sh) — расхождение
		// дало бы «Connected» в UI на туннеле, который лестница уже чинит.
		running: function() {
			if (stat(CONF) == null)
				return true;
			return index(run("pgrep -f '[h]ysteria client -c " + CONF + "' >/dev/null && echo up").out, 'up') >= 0;
		},
		// Маркер runCapture снимается ДО разбора: у скрипта, который не напечатал ничего (файла нет,
		// вывод ушёл в stderr), первой строкой окажется сам "MB_EXIT:<код>". Он не JSON, а json() в
		// ucode на таком БРОСАЕТ — метод hysteria_status умирал бы целиком, и плитка висела бы в
		// «unknown» вместо того, чтобы показать причину из STATE-файла.
		status: function() {
			let line = firstLine(stripExit(run('sh ' + SCRIPT + ' status').out));
			let j = (line != '') ? safeJson(line) : null;
			return (type(j) == 'object') ? j : { state: 'idle', installed: installed(), version: '' };
		},
		// Фон: ~15МБ по медленному/проксированному каналу дольше ubus-таймаута. UI поллит hysteria_status.
		// Замок от повторных нажатий держит сам hysteria.sh — второй запуск выходит сразу.
		install: function() {
			system('sh ' + SCRIPT + ' install >/tmp/mb-hysteria.log 2>&1 &');
			return { status: 'started' };
		},
		// Ждём именно ПОРТ, а не время: холодный старт Go-бинаря с SD на R2S не укладывается в общий
		// sleep пробы, и живой hysteria-кандидат объявлялся бы мёртвым — failover уводил бы с рабочего
		// сервера. Слушающий сокет виден в /proc/net/tcp (порт в hex), внешних утилит для этого не надо.
		probeStart: function(server) {
			if (!installed())
				return false;
			system('pkill -f ' + PROBE_MATCH + ' 2>/dev/null');
			if (writeConf(PROBE_CONF, hysteriaConfigJson(server, { socksPort: PROBE_SOCKS })) != null)
				return false;
			system(BIN + ' client -c ' + PROBE_CONF + ' >/dev/null 2>&1 &');
			system(sprintf("i=0; while [ $i -lt 20 ]; do grep -qi ':%04X ' /proc/net/tcp && break; " +
				"usleep 100000 2>/dev/null || sleep 1; i=$((i+1)); done", PROBE_SOCKS));
			return true;
		},
		probeStop: function() {
			system('pkill -f ' + PROBE_MATCH + ' 2>/dev/null');
			system('rm -f ' + PROBE_CONF);
		},
	};
}

export { hysteriaRuntime };
