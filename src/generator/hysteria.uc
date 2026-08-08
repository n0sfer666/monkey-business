// Генератор конфига hysteria2-клиента + аутбаунда xray, который в него смотрит.
//
// Hysteria — отдельный процесс со своим QUIC-стеком, встроить его в xray нечем. Поэтому связка
// такая: hysteria слушает локальный SOCKS на 127.0.0.1:10810, а аутбаунд "proxy" в xray становится
// socks вместо vless. Вся маршрутизация (сплит, kill-switch, DNS, TPROXY) остаётся на xray и не
// знает, какой протокол под аутбаундом, — поэтому direct идёт в обход ровно так же, как с reality.
//
// hysteriaConfig(server, opts) -> object      hysteriaConfigJson(server, opts) -> string
// hysteriaOutbound(opts) -> аутбаунд xray     isHysteria(server) -> bool

const SOCKS_PORT = 10810;

function isHysteria(s) {
	return s != null && s.protocol == "hysteria2";
}

// IPv6-литерал в адресе обязан быть в скобках: "2001:db8::1:443" клиент разберёт как адрес без
// порта и уедет мимо сервера, не сказав об этом ничего внятного.
function hostPart(a) {
	return (index(a, ":") >= 0) ? "[" + a + "]" : a;
}

// Порт-хоппинг у hysteria задаётся прямо в адресе сервера ("host:10000-20000"), отдельного поля в
// конфиге нет: mport перекрывает обычный порт.
function serverAddress(s) {
	if (s.mport != null && s.mport != "")
		return sprintf("%s:%s", hostPart(s.address), s.mport);
	return sprintf("%s:%d", hostPart(s.address), s.port);
}

function hysteriaConfig(s, opts) {
	opts = opts || {};
	let tls = { sni: s.sni || s.address, insecure: (s.insecure == "1") };
	if (s.pin_sha256 != null && s.pin_sha256 != "")
		tls.pinSHA256 = s.pin_sha256;

	let cfg = {
		server: serverAddress(s),
		auth: s.password || "",
		tls: tls,
		socks5: { listen: sprintf("127.0.0.1:%d", opts.socksPort || SOCKS_PORT) },
		// lazy: не открывать QUIC-сессию до первого запроса — иначе клиент долбится в сервер сразу
		// после старта, ещё до того как поднят маршрут.
		lazy: true,
		fastOpen: true,
	};

	if (s.obfs != null && s.obfs.type == "salamander")
		cfg.obfs = { type: "salamander", salamander: { password: s.obfs.password || "" } };

	// bandwidth намеренно не задаём: без него hysteria использует BBR, который сам подбирает скорость.
	// Заниженные цифры из подписки режут пропускную способность сильнее, чем помогает brutal.
	return cfg;
}

function hysteriaConfigJson(s, opts) {
	return sprintf("%.J", hysteriaConfig(s, opts));
}

function hysteriaOutbound(opts) {
	opts = opts || {};
	return {
		tag: "proxy",
		protocol: "socks",
		settings: { servers: [{ address: "127.0.0.1", port: opts.socksPort || SOCKS_PORT }] },
	};
}

export { isHysteria, hysteriaConfig, hysteriaConfigJson, hysteriaOutbound, serverAddress, SOCKS_PORT };
