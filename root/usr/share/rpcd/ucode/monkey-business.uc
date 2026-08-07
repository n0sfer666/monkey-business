// rpcd ucode-плагин monkey-business (РАНТАЙМ, device-side).
// Регистрирует ubus-объект 'monkey-business' и делегирует логику чистым хендлерам.
// Сам файл — только проводка: контракт ctx собирается из модулей runtime/*.
//
// ВЕРИФИКАЦИЯ: только на устройстве/в dev-VM (нужны модули uci/fs + uclient-fetch +
// init.d + xray). Чистая логика покрыта host-тестами (test/unit/rpcd_test.uc).
//
// Установка (см. packaging): src/* -> /usr/share/rpcd/ucode/lib/monkey-business/*
'use strict';

import * as uci from 'uci';
import { readfile, stat } from 'fs';
// АБСОЛЮТНЫЙ путь: rpcd-mod-ucode компилирует плагин из буфера (без пути к файлу),
// поэтому относительный import не резолвится. Транзитивные импорты в lib/ грузятся из
// файла и остаются относительными. Путь = место установки (см. шапку и deploy/packaging).
import * as h from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/handlers.uc';
import * as hstatus from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/status.uc';
import * as hsub from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/subscription.uc';
import * as hping from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/ping.uc';
import * as huri from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/uri.uc';
import * as hy from '/usr/share/rpcd/ucode/lib/monkey-business/rpcd/hysteria.uc';
import * as sh from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/shell.uc';
import { CONFIG, XRAY_CONF, WD_STATE } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/paths.uc';
import { loadSection, loadServers, storeServers, selectedServer, storeSelected }
	from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/uci.uc';
import { netRuntime } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/net.uc';
import { applyRuntime } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/apply.uc';
import { hysteriaRuntime } from '/usr/share/rpcd/ucode/lib/monkey-business/runtime/hysteria.uc';

const hysteria = hysteriaRuntime(sh.runCapture);
const net = netRuntime(sh, hysteria, stat);
const app = applyRuntime(sh);

function buildCtx() {
	let cursor = uci.cursor();
	return {
		getGlobal: function() { return loadSection(cursor, 'global'); },
		getDns: function() { return loadSection(cursor, 'dns'); },
		getAntiDpi: function() { return loadSection(cursor, 'anti_dpi'); },
		getSubscription: function() { return loadSection(cursor, 'subscription'); },
		getServers: function() { return loadServers(cursor); },
		setServers: function(servers) { storeServers(cursor, servers); },
		getSelectedServer: function() { return selectedServer(cursor); },
		setSelected: function(tag) { storeSelected(sh, tag); },
		setSubscriptionUrl: function(url) {
			cursor.set(CONFIG, 'subscription', 'url', url);
			cursor.commit(CONFIG);
		},
		setUserinfo: function(o) {
			cursor.set(CONFIG, 'subscription', 'used_upload', o.used_upload || '');
			cursor.set(CONFIG, 'subscription', 'used_download', o.used_download || '');
			cursor.set(CONFIG, 'subscription', 'total', o.total || '');
			cursor.set(CONFIG, 'subscription', 'expire', o.expire || '');
			cursor.commit(CONFIG);
		},
		fetchSubscription: function(url) { return net.fetchSubscription(url); },
		pingServer: function(s) { return net.tcpPing(s); },
		probeServer: function(s) {
			return net.probeServer(loadSection(cursor, 'global'), loadSection(cursor, 'dns'), s);
		},
		// Каждая проба — до ~10с. Без потолка 7 серверов = ~70с, что дольше ubus-таймаута:
		// вызов рвался, watchdog читал это как «рабочих серверов нет» и уходил в down,
		// хотя rpcd на той стороне доходил до конца и переключался.
		// 0/не задано = перебирать ВЕСЬ список. Жёсткий дефолт вроде 3 при 7 серверах делал
		// рабочий сервер на 4-й позиции недостижимым ни для watchdog, ни для «Turn on».
		failoverCap: function() {
			let v = int(cursor.get(CONFIG, 'global', 'failover_cap') || 0);
			return (v > 0) ? v : 0;
		},
		watchdogPhase: function() {
			let raw = readfile(WD_STATE);
			if (raw == null)
				return null;
			let m = match(raw, /WD_PHASE=([a-z]+)/);
			return (m != null) ? m[1] : null;
		},
		// Тег mb-event, а не monkey-business: последним под общим тегом почти всегда оказывалась
		// служебная строка apply.sh/flush.sh («tproxy firewall flushed») из init.d, а не причина
		// отказа — а в фазе down init.d дёргается каждый тик.
		lastEvent: function() {
			let r = sh.runCapture('logread -e mb-event 2>/dev/null | tail -n 1');
			return sh.firstLine(sh.stripExit(r.out));
		},
		applyConfig: function(jsonStr, intentOn) { return app.applyConfig(jsonStr, intentOn); },
		stopService: function() { system('/etc/init.d/monkey-business stop'); },
		serviceRunning: function() {
			// Матч по cmdline боевого конфига: `pidof xray` считал живым и эфемерную пробу
			// failover (/tmp/mb-probe.json), и чужой xray из стокового пакета -> UI врал
			// «Connected» при отсутствующем туннеле. pgrep -x не матчит comm в этой сборке
			// BusyBox, а -f (как в pkill выше) работает.
			// hysteria (когда активен именно он) — часть того же туннеля: живой xray с мёртвым
			// клиентом это не «Connected», а трафик в закрытый socks.
			return index(sh.runCapture('pgrep -f ' + sh.shq(sh.noSelfMatch('xray run -c ' + XRAY_CONF)) +
				' >/dev/null && echo up').out, 'up') >= 0 && hysteria.running();
		},
		// Возврат = легло ли намерение в UCI: на read-only rootfs commit не проходит, а туннель к
		// этому моменту уже поднят обходом гейта — вызывающий обязан узнать и свернуть его.
		setEnabled: function(on) {
			cursor.set(CONFIG, 'global', 'enabled', on ? '1' : '0');
			return cursor.commit(CONFIG) === true;
		},
		checkExit: function(domain) { return net.checkExit(domain); },
		// Возврат = легло ли в UCI: файрвол (init.d) читает пару из UCI, а не из памяти курсора, и
		// незаписанный на read-only rootfs режим дал бы «применили» при неизменившемся обходе.
		setMode: function(mode, region) {
			cursor.set(CONFIG, 'global', 'routing_mode', mode);
			cursor.set(CONFIG, 'global', 'local_region', region);
			return cursor.commit(CONFIG) === true;
		},
		// Обход ФАКТИЧЕСКИ включён = в prerouting стоит правило по сету mb_ru4 (его ставит apply.sh
		// только при MB_DIRECT_BYPASS=1). Читаем цепочку, а не сет: в mb_ru4 тысячи RU-CIDR, а
		// status опрашивается раз в 5с. Нет таблицы (VPN выключен) — nft молчит в stderr, и это
		// честный false.
		directBypassActive: function() {
			return index(sh.runCapture('nft list chain inet monkey_business prerouting 2>/dev/null').out,
				'mb_ru4') >= 0;
		},
		hysteriaInstalled: function() { return hysteria.installed(); },
		applyHysteria: function(jsonStr) { return hysteria.apply(jsonStr); },
		hysteriaStatus: function() { return hysteria.status(); },
		hysteriaInstall: function() { return hysteria.install(); },
		setCustomRouting: function(direct, proxy) {
			cursor.set(CONFIG, 'global', 'custom_direct', direct);
			cursor.set(CONFIG, 'global', 'custom_proxy', proxy);
			cursor.commit(CONFIG);
		},
		updateGeo: function(args) {
			// сохранить кастомные URL (commit на сервере, без LuCI-стейджинга)
			if (args != null && (args.geoip_url != null || args.geosite_url != null)) {
				cursor.set(CONFIG, 'geo', 'geoip_url', args.geoip_url || '');
				cursor.set(CONFIG, 'geo', 'geosite_url', args.geosite_url || '');
				cursor.commit(CONFIG);
			}
			return app.updateGeo();
		},
		geoStatus: function() { return app.geoStatus(); },
		geoInstall: function(which) { return app.geoInstall(which); },
	};
}

const methods = {
	status:               { call: function() { return hstatus.status(buildCtx()); } },
	servers_list:         { call: function() { return hstatus.serversList(buildCtx()); } },
	servers_ping:         { call: function() { return hping.serversPing(buildCtx()); } },
	subscription_update:  { args: { url: '' }, call: function(req) { return hsub.subscriptionUpdate(buildCtx(), req.args); } },
	parse_uri:            { args: { uri: '', section: '' }, call: function(req) { return huri.parseServerUri(buildCtx(), req.args); } },
	config_apply:         { call: function() { return h.configApply(buildCtx()); } },
	service_toggle:       { args: { enabled: false }, call: function(req) { return h.serviceToggle(buildCtx(), req.args); } },
	geo_update:           { args: { geoip_url: '', geosite_url: '' }, call: function(req) { return h.geoUpdate(buildCtx(), req.args); } },
	set_routing:          { args: { direct: '', proxy: '' }, call: function(req) { return h.setRouting(buildCtx(), req.args); } },
	set_mode:             { args: { mode: '', region: '' }, call: function(req) { return h.setMode(buildCtx(), req.args); } },
	geo_status:           { call: function() { return h.geoStatus(buildCtx()); } },
	geo_install:          { args: { which: '' }, call: function(req) { return h.geoInstall(buildCtx(), req.args); } },
	check_exit:           { args: { domain: '' }, call: function(req) { return h.checkExit(buildCtx(), req.args); } },
	hysteria_status:      { call: function() { return hy.hysteriaStatus(buildCtx()); } },
	hysteria_install:     { call: function() { return hy.hysteriaInstall(buildCtx()); } },
};

return { 'monkey-business': methods };
