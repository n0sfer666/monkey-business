// Установка сгенерированного конфига на живой xray: валидация, атомарная подмена файла, reload.
// Здесь же geo — конфиг без geo-баз xray не примет, и отказ должен быть внятным, а не «bad config».

import { readfile, writefile, stat } from 'fs';
import { CONF_DIR, XRAY_CONF, GEO_DIR, GEO_SCRIPT, WD_STATE } from './paths.uc';

// Размер, а не только наличие: оборванная закачка оставляет .dat в пару килобайт — проверка
// на null проходит, а xray потом падает на старте с невнятной ошибкой парсинга гео-базы.
function geoPresent() {
	let ip = stat(GEO_DIR + '/geoip.dat'), site = stat(GEO_DIR + '/geosite.dat');
	return ip != null && site != null && ip.size > 0 && site.size > 0;
}

function applyRuntime(sh) {
	// Валидирует конфиг реальным xray, при успехе устанавливает + поднимает сервис.
	// Возврат: строка-ошибка | null(успех).
	//
	// Установка атомарная: пишем в соседний .tmp на ТОМ ЖЕ разделе, валидируем именно тот файл,
	// что ляжет на место (а не /tmp-копию), и только потом rename. Раньше обрыв на writefile
	// оставлял обрезанный xray.json, а `restart` всё равно звался -> сервис не поднимался.
	// intentOn=true: reload идёт с MB_INTENT=1 — init-скрипт поднимается, не глядя на ещё не
	// выставленный тумблер. Нужен только пути включения (service_toggle); остальные вызовы обязаны
	// упираться в гейт, иначе config_apply при выключенном VPN снова поднимал бы туннель молча.
	function applyConfig(jsonStr, intentOn) {
		let reload = (intentOn ? 'MB_INTENT=1 ' : '') + '/etc/init.d/monkey-business reload >/dev/null 2>&1';
		system('mkdir -p ' + CONF_DIR);
		if (!geoPresent())
			return 'geo databases missing — press "Update geo databases" on the Dashboard first';

		// Байт-в-байт тот же конфиг — не трогаем карту вообще. Это не микрооптимизация: в фазе `down`
		// watchdog зовёт config_apply раз в BACKOFF, а когда рабочих серверов нет, selectWorking каждый
		// раз возвращает один и тот же servers[0] -> без этой проверки один и тот же файл ложился бы на
		// SD 144 раза в сутки. Валидацию тоже пропускаем: этот файл уже прошёл её, когда его писали.
		if (readfile(XRAY_CONF) == jsonStr) {
			system(reload);
			system('rm -f ' + WD_STATE);
			return null;
		}

		// Расширение .json обязательно: xray выбирает парсер по filepath.Ext(), и `-test -c *.tmp`
		// провалился бы на валидном конфиге.
		let tmp = CONF_DIR + '/.xray.new.json';
		if (writefile(tmp, jsonStr) != length(jsonStr)) {
			system('rm -f ' + tmp);
			return 'failed to write config (disk full?)';
		}
		let v = sh.runCapture('xray run -test -c ' + tmp + ' 2>/tmp/mb-xray.err');
		if (!v.ok) {
			let err = readfile('/tmp/mb-xray.err');
			let msg = sh.firstLine(err != null ? err : v.out);
			system('rm -f ' + tmp);
			return (msg != '') ? msg : 'xray config validation failed';
		}
		// Без sync: rename в ext4 и так атомарен относительно журнала, а принудительный сброс на каждый
		// apply — это read-modify-write сегмента FTL ради данных, которые ядро всё равно допишет само.
		if (!sh.runCapture('mv ' + tmp + ' ' + XRAY_CONF).ok) {
			system('rm -f ' + tmp);
			return 'failed to install config';
		}

		// НЕ restart: stop_service гонит flush.sh и снимает kill-switch, а окно до подъёма xray —
		// это утечка LAN в открытую сеть. reload_service переобъявляет инстанс, procd видит смену
		// хеша файла-триггера (procd_set_param file $CONF) и перезапускает только процесс xray.
		system(reload);
		// Фаза watchdog описывает СТАРЫЙ конфиг; оставленный `down` заставил бы UI врать
		// «Disabled by watchdog» сразу после успешного применения.
		system('rm -f ' + WD_STATE);
		return null;
	}

	function updateGeo() {
		// фон: скачивание ~29MB дольше ubus-таймаута (30s). UI поллит geo_status.
		system('sh ' + GEO_SCRIPT + ' download >/tmp/mb-geo.log 2>&1 &');
		return { status: 'started' };
	}

	function geoStatus() {
		let line = sh.firstLine(sh.stripExit(sh.runCapture('sh ' + GEO_SCRIPT + ' status').out));
		let j = (line != '') ? json(line) : null;
		return (type(j) == 'object') ? j : { state: 'idle', geoip: 0, geosite: 0 };
	}

	function geoInstall(which) {
		// defense-in-depth: whitelist и здесь (which идёт в команду + имя файла)
		if (which != "geoip" && which != "geosite")
			return { ok: false, detail: "bad which" };
		let r = sh.runCapture('sh ' + GEO_SCRIPT + ' install ' + which + ' /tmp/mb-upload-' + which + '.dat 2>&1');
		return { ok: r.ok, detail: sh.firstLine(sh.stripExit(r.out)) };
	}

	return {
		applyConfig: applyConfig,
		updateGeo: updateGeo,
		geoStatus: geoStatus,
		geoInstall: geoInstall,
	};
}

export { applyRuntime };
