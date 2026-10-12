import { connect } from 'ubus';
import { cursor } from 'uci';

const CONF = 'monkey-business';
const SUB_URL = getenv('MB_FIXTURE_URL');
const SUB_NAME = 'Fixture';
const OFF_TAG = '🇫🇮 Helsinki · off';
const MANUAL_TAG = '✎ Manual · Warsaw';
const MANUAL_LINK = 'vless://9c1d7e5a-3b2f-4a8c-b6e0-1f7d2c9a4e33@198.51.100.20:8443?type=tcp&security=reality&sni=www.amazon.com&pbk=jNXHt1yRo0vDuSWqGlN-hy5JEhTX6XiDSVQOGXWD8Ss&sid=ef56&flow=xtls-rprx-vision&fp=firefox#manual';

if (!SUB_URL)
	die('MB_FIXTURE_URL не задан');

let bus = connect(null, 90);
if (bus == null)
	die('ubus недоступен');

function sections(u, type_) {
	let out = [];
	u.foreach(CONF, type_, function(s) { push(out, s); });
	return out;
}

function find(list, key, value) {
	return filter(list, function(s) { return s[key] == value; })[0];
}

function syncSubscription() {
	let have = find(sections(cursor(), 'subscription'), 'name', SUB_NAME);
	let r = (have != null)
		? bus.call('monkey-business', 'subscription_update', { sub: have['.name'], url: SUB_URL })
		: bus.call('monkey-business', 'subscription_add', { name: SUB_NAME, url: SUB_URL });
	if (r == null || r.error != null)
		die(sprintf('подписка: %J', r));
	print(sprintf('>> фикстура: подписка %s, серверов %d\n', (have != null) ? 'обновлена' : 'добавлена', r.added));
}

function addManual(u) {
	if (find(sections(u, 'server'), 'tag', MANUAL_TAG) != null)
		return print('>> фикстура: ручной сервер уже есть\n');
	let p = bus.call('monkey-business', 'parse_uri', { uri: MANUAL_LINK, section: '' });
	if (p == null || p.ok != true)
		die(sprintf('parse_uri: %J', p));
	let sid = u.add(CONF, 'server');
	for (let k, v in p.server)
		if (v != null && v != '')
			u.set(CONF, sid, k, '' + v);
	u.set(CONF, sid, 'tag', MANUAL_TAG);
	print('>> фикстура: ручной сервер добавлен\n');
}

syncSubscription();
let u = cursor();
let sub = find(sections(u, 'subscription'), 'name', SUB_NAME);
if (sub == null)
	die('подписка ' + SUB_NAME + ' не записалась');
u.set(CONF, sub['.name'], 'auto_update', '0');
let off = find(sections(u, 'server'), 'tag', OFF_TAG);
if (off == null)
	die('нет сервера ' + OFF_TAG);
u.set(CONF, off['.name'], 'disabled', '1');
addManual(u);
u.commit(CONF);
let a = bus.call('monkey-business', 'config_apply', {});
print(sprintf('>> фикстура: config_apply %s\n', (a != null && a.error == null) ? 'ок' : sprintf('%J', a)));
