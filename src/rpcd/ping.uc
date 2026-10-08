// Замер latency по всему списку серверов (кнопка «Test latency» в UI). Это не выбор сервера:
// результат никуда не применяется, порядок и активный сервер не меняются.

import { listedServers } from "./select.uc";
import { serverId } from "../lib/subs.uc";

function serversPing(ctx) {
	let results = [];
	let best = null, bestId = null, bestMs = null;
	for (let s in listedServers(ctx)) {
		let ms = ctx.pingServer(s);
		push(results, { id: serverId(s), tag: s.tag, latency_ms: ms });
		if (ms != null && (bestMs == null || ms < bestMs)) {
			bestMs = ms;
			best = s.tag;
			bestId = serverId(s);
		}
	}
	return { results: results, best: best, best_id: bestId };
}

export { serversPing };
