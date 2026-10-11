const GEOSITE = '/usr/share/xray/geosite.dat';
const GEO_OFF = `if [ -f ${GEOSITE}.uidiff ]; then rm -f ${GEOSITE}; else mv ${GEOSITE} ${GEOSITE}.uidiff; fi
if [ -f ${GEOSITE} ]; then echo 'geosite.dat is still there' >&2; exit 1; fi`;
const GEO_ON = `if [ -f ${GEOSITE}.uidiff ]; then mv ${GEOSITE}.uidiff ${GEOSITE}; fi`;
const CONF = '/etc/config/monkey-business';
const NO_LIMIT = `[ -f /tmp/mb-uidiff.conf ] || cp ${CONF} /tmp/mb-uidiff.conf
for s in $(uci show monkey-business | sed -n 's/^monkey-business\\.\\([^.=]*\\)=subscription$/\\1/p'); do uci -q delete monkey-business.$s.total || true; done
uci commit monkey-business
if uci show monkey-business | grep -q '[.]total='; then echo 'traffic limit is still set' >&2; exit 1; fi`;
const RESTORE = `if [ -f /tmp/mb-uidiff.conf ]; then cp /tmp/mb-uidiff.conf ${CONF}; rm /tmp/mb-uidiff.conf; fi`;

const BOARDS = [
	{ screen: 'dashboard', board: 'Main', width: 1280, page: 'dashboard', props: {} },
	{ screen: 'dashboard', board: 'Main', state: 'missing', width: 1280, page: 'dashboard', props: { geo: 'missing' }, setup: GEO_OFF, teardown: GEO_ON },
	{ screen: 'dashboard', board: 'Main', state: 'unlimited', width: 1280, page: 'dashboard', props: { traffic: 'unlimited' }, setup: NO_LIMIT, teardown: RESTORE },
	{ screen: 'dashboard', board: 'Main', state: 'hidden', width: 1280, page: 'dashboard', props: {}, boardClick: ['button:has-text("Hide traffic")'], standClick: ['.mb-dash-traf button.mb-link'] },
	{ screen: 'dashboard', board: 'MobileDashboard', width: 390, page: 'dashboard', props: {} },
	{ screen: 'dashboard', board: 'MobileDashboard', state: 'missing', width: 390, page: 'dashboard', props: { geo: 'missing' }, setup: GEO_OFF, teardown: GEO_ON },
	{ screen: 'servers', board: 'Servers', width: 1280, page: 'servers', props: {} },
	{ screen: 'servers', board: 'MobileServers', state: 'list', width: 390, page: 'servers', props: {}, boardClick: ['button[aria-label="Reorder servers"]'] },
	{ screen: 'servers', board: 'MobileServers', state: 'arrange', width: 390, page: 'servers', props: {}, standClick: ['.mb-srvs-gear', '.mb-tile:nth-child(3)'] },
	{ screen: 'settings', board: 'Settings', width: 1280, page: 'settings', props: {} },
	{ screen: 'settings', board: 'MobileSettings', width: 390, page: 'settings', props: {} },
];

const DEFAULTS = { boardRoot: 'frame', implRoot: '#view', state: '', boardClick: [], standClick: [], setup: '', teardown: '' };

function select(screen, width) {
	return BOARDS
		.filter(b => (!screen || b.screen === screen || b.board === screen) && (!width || b.width === width))
		.map(b => Object.assign({}, DEFAULTS, b, { label: b.state ? b.board + '-' + b.state : b.board }));
}

module.exports = { BOARDS, select };
