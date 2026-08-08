// Чистые rpcd-хендлеры, меняющие состояние: применение конфига, тумблер, режим/правила, geo.
// Чтение (status/servers_list) — в status.uc, подписка — в subscription.uc, выбор сервера — в
// select.uc, замер пинга — в ping.uc. Зависимости (uci/ubus/сеть/файлы) инкапсулированы в `ctx` —
// это держит логику host-тестируемой. Рантайм-привязка ctx — в root/usr/share/rpcd/ucode/monkey-business.uc.
//
// Контракт ctx:
//   getGlobal() -> { enabled, routing_mode, local_region, tproxy_port, custom_direct, custom_proxy, ... }
//   getDns() -> { mode, direct_dns, doh_url }   getAntiDpi() -> { default_fingerprint, xhttp_padding }
//   getSubscription() -> { url, used_upload, used_download, total, expire, ... }
//   getServers() -> [server, ...]      setServers(arr)
//   getSelectedServer() -> server|null   setSelected(tag) — рантайм-состояние, НЕ uci-commit
//   fetchSubscription(url) -> { body, userinfo }|null   pingServer(server) -> int(ms)|null
//   applyConfig(jsonStr, intentOn?) -> errString|null (валидирует + запускает; intentOn=true обходит
//     гейт по enabled в init-скрипте — только для пути включения)   stopService()
//   serviceRunning() -> bool   setEnabled(bool) -> bool (легло ли в UCI)   updateGeo(args) -> { status }
//   failoverCap() -> int (сколько кандидатов пробовать в selectWorking; 0 = все)
//   watchdogPhase() -> "healthy"|"reconnecting"|"down"|null   lastEvent() -> string
//   setCustomRouting(direct, proxy)   setMode(mode, region) -> bool (легло ли в UCI)
//   directBypassActive() -> bool (ФАКТ из nft, не намерение)   geoStatus() -> { state, geoip, geosite }
//   geoInstall(which) -> { ok, detail }   checkExit(domain) -> { ip, country, code }|{ error }
//   hysteriaInstalled() -> bool   applyHysteria(jsonStr|null) -> errString|null

import { isTrue } from "../lib/val.uc";
import { generateJson } from "../generator/xray.uc";
import { selectWorking } from "./select.uc";
import { directBypass } from "../lib/bypass.uc";
import { prepareHysteria } from "./hysteria.uc";

const ROUTING_MODES = ["bypass-local", "gfwlist", "global"];
const LOCAL_REGIONS = ["ru", "cn", "ir", "other"];

function genConfig(ctx, server) {
	return {
		global: ctx.getGlobal(),
		server: server,
		dns: ctx.getDns(),
		anti_dpi: ctx.getAntiDpi(),
		test_socks: true,
		dns_transparent: true,
	};
}

// При выключенном VPN рантайм не трогаем вообще: init-скрипт всё равно не поднимет xray (гейт по
// enabled), а без раннего выхода мы бы зря поднимали эфемерный xray на пробу серверов и меняли
// активный сервер. `skipped` нужен UI, чтобы не врать «applied», когда ничего не применялось.
function configApply(ctx) {
	if (!isTrue(ctx.getGlobal().enabled))
		return { ok: true, skipped: "disabled" };
	let sel = selectWorking(ctx);
	if (sel == null)
		return { error: "no servers — add a subscription or a manual server first" };
	let hErr = prepareHysteria(ctx, sel.server);
	if (hErr != null)
		return { error: hErr };
	let jsonStr = generateJson(genConfig(ctx, sel.server));
	let err = ctx.applyConfig(jsonStr);
	if (err != null)
		return { error: err };
	return { ok: true, server: sel.server.tag, probed: sel.probed, bytes: length(jsonStr) };
}

function serviceToggle(ctx, args) {
	let on = (args != null) && isTrue(args.enabled);
	if (!on) {
		ctx.setEnabled(false);
		ctx.stopService();
		return { enabled: false };
	}
	let sel = selectWorking(ctx);
	if (sel == null)
		return { error: "no servers — add a subscription first", enabled: false };
	let hErr = prepareHysteria(ctx, sel.server);
	if (hErr != null)
		return { error: hErr, enabled: isTrue(ctx.getGlobal().enabled) };
	let jsonStr = generateJson(genConfig(ctx, sel.server));
	// Сначала поднять туннель (intentOn=true — явный обход гейта по enabled), только потом commit
	// тумблера. Обратный порядок (setEnabled -> applyConfig) держал enabled=1 всё время пробы
	// серверов: cron-watchdog видел intent=1 без xray и поднимал СТАРЫЙ конфиг себе под ноги.
	// enabled в ответе — фактическое состояние: гасить его на ошибке нельзя, xray мог остаться на
	// прежнем валидном конфиге, и watchdog перестал бы за ним следить.
	let err = ctx.applyConfig(jsonStr, true);
	if (err != null)
		return { error: err, enabled: isTrue(ctx.getGlobal().enabled) };
	// Намерение обязано лечь в UCI: туннель уже поднят обходом гейта, и незаписанный enabled (rootfs
	// в read-only) оставил бы xray с kill-switch'ем, за которым не следит никто — watchdog смотрит в
	// UCI, дашборд пишет «off», reload отказывается и правила не снимает. Не легло — сворачиваем.
	if (!ctx.setEnabled(true)) {
		ctx.stopService();
		return { error: "could not save the toggle state (read-only config?)", enabled: false };
	}
	return { enabled: true, server: sel.server.tag, probed: sel.probed };
}

function geoUpdate(ctx, args) {
	return ctx.updateGeo(args);
}

// Записать custom direct/proxy в UCI (commit на стороне сервера, без LuCI-стейджинга) и применить.
function setRouting(ctx, args) {
	let direct = (args != null && args.direct != null) ? args.direct : "";
	let proxy = (args != null && args.proxy != null) ? args.proxy : "";
	ctx.setCustomRouting(direct, proxy);
	return configApply(ctx);
}

// Режим маршрутизации + регион переехали из формы Settings на дашборд: они меняют не только конфиг
// xray, но и файрвол (ядерный обход), а форма LuCI умеет только стейджить UCI — «сохранил и ничего
// не изменилось» здесь особенно дорого. Пишем и применяем сразу, как setRouting. Пустое значение =
// «не трогать»: UI шлёт оба поля, но ubus-контракт допускает частичный вызов.
function setMode(ctx, args) {
	let g = ctx.getGlobal();
	let prevMode = g.routing_mode || "bypass-local";
	let prevRegion = g.local_region || "ru";
	let mode = (args != null && args.mode != null && args.mode != "") ? args.mode : prevMode;
	let region = (args != null && args.region != null && args.region != "") ? args.region : prevRegion;
	// Значения идут в конфиг xray как имена geo-категорий (geoip:<region>): мусор отсюда — это
	// `xray -test` на каждом apply, то есть отказ применять ЛЮБЫЕ настройки до ручной правки UCI.
	if (index(ROUTING_MODES, mode) < 0)
		return { error: "bad routing mode" };
	if (index(LOCAL_REGIONS, region) < 0)
		return { error: "bad local region" };
	if (!ctx.setMode(mode, region))
		return { error: "could not save the routing mode (read-only config?)" };
	let res = configApply(ctx);
	// Пара уже в UCI, а xray.json перегенерируется ТОЛЬКО успешным apply — при этом ядерный обход
	// init-скрипт считает из UCI. Провал оставил бы файрвол по новой паре, а туннель по старому
	// конфигу, и расхождение пережило бы ребут (start_service конфиг не пересобирает). Не
	// применилось — откатываем пару, чтобы оба источника остались на прежнем согласованном наборе.
	if (res.error != null) {
		ctx.setMode(prevMode, prevRegion);
		return res;
	}
	res.mode = mode;
	res.region = region;
	res.direct_bypass = directBypass(ctx.getGlobal());
	return res;
}

function geoStatus(ctx) {
	return ctx.geoStatus();
}

function geoInstall(ctx, args) {
	let which = (args != null) ? args.which : null;
	if (which != "geoip" && which != "geosite")
		return { error: "bad which (geoip|geosite)" };
	return ctx.geoInstall(which);
}

// Проверка сплита: запрос к гео-сервису через тестовый SOCKS-inbound -> по каким правилам ушёл
// (proxy/direct), какой выходной IP/страна. domain = гео-сервис (по умолчанию ip-api.com).
function checkExit(ctx, args) {
	let domain = (args != null) ? args.domain : null;
	return ctx.checkExit(domain);
}

export { configApply, serviceToggle, geoUpdate, setRouting, setMode, geoStatus, geoInstall, checkExit };
