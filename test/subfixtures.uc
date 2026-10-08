import { serverId, findSub, findSelected } from "../src/lib/subs.uc";

const NOW = 1800000000;

function srv(tag, address, sub) {
	return { tag: tag, protocol: "vless", address: address, port: 443, uuid: "u-" + address,
		security: "none", sni: "", alpn: [], reality: null,
		transport: { type: "tcp", path: "", host: "", mode: "", serviceName: "" },
		source: "subscription", sub: sub };
}

function manual(tag, address) {
	let s = srv(tag, address, null);
	s.source = "manual";
	delete s.sub;
	return s;
}

function sub(id, extra) {
	let s = { ".name": id, name: "N-" + id };
	for (let k in extra)
		s[k] = extra[k];
	return s;
}

function tags(list) {
	return map(list, function(s) { return s.tag; });
}

function ids(list) {
	return map(list, function(s) { return s.id; });
}

function mkState(servers, subs, active) {
	return {
		global: { enabled: "1", routing_mode: "bypass-local", local_region: "ru", tproxy_port: 12345,
			active_sub: active },
		dns: { mode: "split", direct_dns: "77.88.8.8", doh_url: "https://1.1.1.1/dns-query" },
		anti_dpi: { default_fingerprint: "chrome", xhttp_padding: "0" },
		subs: subs, servers: servers, selected: "", probeFail: {}, applyErr: null, applies: 0, writes: 0,
	};
}

function mockCtx(st) {
	return {
		getGlobal: function() { return st.global; },
		getDns: function() { return st.dns; },
		getAntiDpi: function() { return st.anti_dpi; },
		getSubscriptions: function() { return st.subs; },
		getSubscription: function(id) { return findSub(st.subs, id); },
		setActiveSub: function(id) {
			st.writes++;
			if (st.setFail)
				return false;
			st.global.active_sub = id;
			return true;
		},
		getServers: function() { return st.servers; },
		getSelectedServer: function() { return findSelected(st.servers, st.selected); },
		getSelectedId: function() { return st.selected; },
		setSelected: function(id) { st.selected = id; },
		probeServer: function(s) { return st.probeFail[serverId(s)] !== true; },
		applyConfig: function(j) {
			st.applies++;
			st.applied = j;
			return st.applyErr;
		},
		serviceRunning: function() { return true; },
	};
}

function mockCursor(sections) {
	let n = 0;
	return {
		sections: sections,
		foreach: function(config, type_, cb) {
			for (let s in slice(sections))
				if (s[".type"] == type_)
					cb(s);
		},
		delete: function(config, name) {
			sections = filter(sections, function(s) { return s[".name"] != name; });
		},
		add: function(config, type_) {
			let name = "cfg" + n++;
			push(sections, { ".name": name, ".type": type_ });
			return name;
		},
		set: function(config, name, k, v) {
			for (let s in sections)
				if (s[".name"] == name)
					s[k] = v;
		},
		commit: function() { return true; },
		all: function() { return sections; },
	};
}

export { NOW, srv, manual, sub, tags, ids, mkState, mockCtx, mockCursor };
