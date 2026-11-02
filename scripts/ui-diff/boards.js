const GEOSITE = '/usr/share/xray/geosite.dat';
const GEO_OFF = `if [ -f ${GEOSITE}.uidiff ]; then rm -f ${GEOSITE}; else mv ${GEOSITE} ${GEOSITE}.uidiff; fi
if [ -f ${GEOSITE} ]; then echo 'geosite.dat is still there' >&2; exit 1; fi`;
const GEO_ON = `if [ -f ${GEOSITE}.uidiff ]; then mv ${GEOSITE}.uidiff ${GEOSITE}; fi`;
const CONF = '/etc/config/monkey-business';
const NO_LIMIT = `[ -f /tmp/mb-uidiff.conf ] || cp ${CONF} /tmp/mb-uidiff.conf
for s in $(uci show monkey-business | sed -n 's/^monkey-business\\.\\([^.=]*\\)=subscription$/\\1/p'); do uci -q delete monkey-business.$s.total || true; done
uci commit monkey-business
if uci show monkey-business | grep -q '[.]total='; then echo 'traffic limit is still set' >&2; exit 1; fi`;
const SAVE = `[ -f /tmp/mb-uidiff.conf ] || cp ${CONF} /tmp/mb-uidiff.conf`;
const RESTORE = `if [ -f /tmp/mb-uidiff.conf ]; then cp /tmp/mb-uidiff.conf ${CONF}; rm /tmp/mb-uidiff.conf; fi`;

const BAD = {
  direct: [
    '*.yandex.ru',
    'gosuslugi.ru',
    'sberbank.ru',
    'geosite:category-gov-ru',
    '192.168.10.0/24',
    '10.8.0.0/33',
  ].join('\n'),
  proxy: [
    '*.openai.com',
    'geosite:telegram',
    'youtube.',
    'geoip:telegram',
    'https://chatgpt.com/c/1',
    '149.154.160.0/20',
    'claude.ai',
    '*.notion.so',
  ].join('\n'),
};
const GOOD = {
  direct: BAD.direct.replace('/33', '/24'),
  proxy: BAD.proxy.replace('youtube.', 'youtube.com').replace('https://chatgpt.com/c/1', 'chatgpt.com'),
};
const GEO_URL = 'https://example.org/geosite.dat';

function uciSet(pairs) {
  return [SAVE]
    .concat(
      Object.keys(pairs).map((k) => `uci set monkey-business.${k}='${String(pairs[k]).replace(/'/g, "'\\''")}'`),
      ['uci commit monkey-business'],
    )
    .join('\n');
}

function rules(t) {
  return uciSet({ 'global.custom_direct': t.direct, 'global.custom_proxy': t.proxy });
}

const MODAL = {
  fixed: true,
  boardRoot: '[role=dialog]',
  implRoot: '.mb-sheet',
  page: 'dashboard',
  props: {},
  teardown: RESTORE,
};
const ROUTING = Object.assign({}, MODAL, { screen: 'RoutingModal', standClick: ['.mb-dash-redit'] });
const MROUTING = Object.assign({}, ROUTING, {
  screen: 'MobileRoutingModal',
  board: 'MobileRoutingModal',
  width: 390,
  setup: rules(BAD),
});
const GEO = Object.assign({}, MODAL, {
  screen: 'GeoModal',
  standClick: ['button.mb-link:text-is("Update…")'],
  standWait: '.mb-geo-sheet',
  setup: uciSet({ 'geo.geoip_url': '', 'geo.geosite_url': GEO_URL }),
});

const BOARDS = [
  { screen: 'dashboard', board: 'Main', width: 1280, page: 'dashboard', props: {} },
  {
    screen: 'dashboard',
    board: 'Main',
    state: 'missing',
    width: 1280,
    page: 'dashboard',
    props: { geo: 'missing' },
    setup: GEO_OFF,
    teardown: GEO_ON,
  },
  {
    screen: 'dashboard',
    board: 'Main',
    state: 'unlimited',
    width: 1280,
    page: 'dashboard',
    props: { traffic: 'unlimited' },
    setup: NO_LIMIT,
    teardown: RESTORE,
  },
  {
    screen: 'dashboard',
    board: 'Main',
    state: 'hidden',
    width: 1280,
    page: 'dashboard',
    props: {},
    boardClick: ['button:has-text("Hide traffic")'],
    standClick: ['.mb-dash-traf button.mb-link'],
  },
  { screen: 'dashboard', board: 'MobileDashboard', width: 390, page: 'dashboard', props: {} },
  {
    screen: 'dashboard',
    board: 'MobileDashboard',
    state: 'missing',
    width: 390,
    page: 'dashboard',
    props: { geo: 'missing' },
    setup: GEO_OFF,
    teardown: GEO_ON,
  },
  { screen: 'servers', board: 'Servers', width: 1280, page: 'servers', props: {} },
  {
    screen: 'servers',
    board: 'MobileServers',
    state: 'list',
    width: 390,
    page: 'servers',
    props: {},
    boardClick: ['button[aria-label="Reorder servers"]'],
  },
  {
    screen: 'servers',
    board: 'MobileServers',
    state: 'arrange',
    width: 390,
    page: 'servers',
    props: {},
    standClick: ['.mb-srvs-gear', '.mb-tile:nth-child(3)'],
  },
  { screen: 'settings', board: 'Settings', width: 1280, page: 'settings', props: {} },
  { screen: 'settings', board: 'MobileSettings', width: 390, page: 'settings', props: {} },
  Object.assign({}, ROUTING, {
    board: 'RoutingModal',
    state: 'errors',
    width: 1280,
    setup: rules(BAD),
    standWait: '.mb-cr-errs:not([hidden])',
  }),
  Object.assign({}, ROUTING, {
    board: 'RoutingModal',
    state: 'clean',
    width: 1280,
    setup: rules(GOOD),
    standWait: '.mb-cr-errs[hidden]',
    boardFill: [
      ['#crd', GOOD.direct],
      ['#crp', GOOD.proxy],
    ],
  }),
  Object.assign({}, MROUTING, { state: 'errors', standWait: '.mb-cr-errs:not([hidden])' }),
  Object.assign({}, MROUTING, {
    state: 'direct',
    boardClick: ['button[role=tab]:has-text("Direct")'],
    standClick: ['.mb-dash-redit', '.mb-cr-tab:has-text("Direct")'],
    standWait: '.mb-cr-errs:not([hidden])',
  }),
  Object.assign({}, GEO, { board: 'GeoModal', width: 1280 }),
  Object.assign({}, GEO, { screen: 'MobileGeoModal', board: 'MobileGeoModal', width: 390 }),
];

const DEFAULTS = {
  boardRoot: 'frame',
  implRoot: '#view',
  state: '',
  boardClick: [],
  boardFill: [],
  standClick: [],
  standWait: '',
  fixed: false,
  setup: '',
  teardown: '',
};

function select(screen, width) {
  return BOARDS.filter(
    (b) => (!screen || b.screen === screen || b.board === screen) && (!width || b.width === width),
  ).map((b) => Object.assign({}, DEFAULTS, b, { label: b.state ? b.board + '-' + b.state : b.board }));
}

module.exports = { BOARDS, select };
