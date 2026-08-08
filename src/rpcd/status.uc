// Всё, что уходит в UI на чтение: сводный статус и список серверов. Тут же маскирование секретов —
// эти два метода лежат в read-группе ACL, то есть доступны шире, чем управление.

import { isTrue } from "../lib/val.uc";
import { directBypass } from "../lib/bypass.uc";
import { orderedServers } from "./select.uc";

function maskUuid(u) {
	if (u == null || length(u) < 12)
		return "****";
	return substr(u, 0, 4) + ".." + substr(u, length(u) - 4);
}

// wd_phase: healthy|reconnecting|down|null(watchdog ещё не тикал / выключен). Фаза `down`
// означает, что watchdog СНЯЛ туннель и LAN идёт напрямую — без этого UI показывал
// «Starting…» и выглядел как «сейчас поднимется», хотя ничего уже не поднималось.
function status(ctx) {
	let g = ctx.getGlobal();
	let s = ctx.getSelectedServer();
	let sub = ctx.getSubscription();
	// last_event читается только в проблемных фазах: UI показывает его лишь в плашке
	// down/reconnecting, а status опрашивается раз в 5с — дампить за ним весь syslog постоянно
	// значит жечь CPU роутера на строку, которую никто не видит.
	let wd = ctx.watchdogPhase ? ctx.watchdogPhase() : null;
	let noisy = (wd == "down" || wd == "reconnecting");
	return {
		enabled: isTrue(g.enabled),
		running: ctx.serviceRunning(),
		server: (s != null) ? s.tag : null,
		protocol: (s != null) ? (s.protocol || "vless") : null,
		routing_mode: g.routing_mode,
		local_region: g.local_region,
		// ФАКТ из nft, а не намерение из UCI: индикатор обхода — это индикатор утечки, и он обязан
		// показывать применённое. Пара в UCI может разойтись с файрволом (ручная правка uci, провал
		// apply, VPN выключен -> правил нет вовсе). Нет ctx.directBypassActive — фолбэк на расчёт.
		direct_bypass: ctx.directBypassActive ? ctx.directBypassActive() : directBypass(g),
		wd_phase: wd,
		last_event: (noisy && ctx.lastEvent) ? ctx.lastEvent() : "",
		traffic: {
			used_upload: sub.used_upload || "",
			used_download: sub.used_download || "",
			total: sub.total || "",
			expire: sub.expire || "",
		},
	};
}

function serversList(ctx) {
	let out = [];
	let i = 0;
	for (let s in orderedServers(ctx)) {
		push(out, {
			tag: s.tag,
			protocol: s.protocol || "vless",
			address: s.address,
			port: s.port,
			security: s.security,
			transport: (s.transport != null) ? s.transport.type : "tcp",
			priority: i,
			insecure: (s.insecure == "1"),
			// У vless в uuid 36 случайных символов, и края маски безобидны. У hysteria учётные данные
			// живут в password, а uuid парсер оставляет пустым — но секция UCI правится и руками,
			// и попавший в uuid пароль ушёл бы краями в браузер на каждый рендер дашборда
			// (servers_list в read-группе ACL). Сам password наружу не отдаём вообще.
			uuid_masked: (s.protocol == "hysteria2") ? "****" : maskUuid(s.uuid),
		});
		i++;
	}
	return { servers: out };
}

export { status, serversList, maskUuid };
