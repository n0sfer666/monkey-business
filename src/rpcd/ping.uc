// Замер latency по всему списку серверов (кнопка «Test latency» в UI). Это не выбор сервера:
// результат никуда не применяется, порядок и активный сервер не меняются.

import { orderedServers } from "./select.uc";

function serversPing(ctx) {
	let results = [];
	let best = null, bestMs = null;
	for (let s in orderedServers(ctx)) {
		let ms = ctx.pingServer(s);
		push(results, { tag: s.tag, latency_ms: ms });
		if (ms != null && (bestMs == null || ms < bestMs)) {
			bestMs = ms;
			best = s.tag;
		}
	}
	return { results: results, best: best };
}

export { serversPing };
