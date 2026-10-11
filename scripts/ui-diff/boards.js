const BOARDS = [
	{ screen: 'dashboard', board: 'Main', width: 1280, page: 'dashboard', props: {} },
	{ screen: 'dashboard', board: 'MobileDashboard', width: 390, page: 'dashboard', props: {} },
	{ screen: 'servers', board: 'Servers', width: 1280, page: 'servers', props: {} },
	{ screen: 'servers', board: 'MobileServers', width: 390, page: 'servers', props: {} },
	{ screen: 'settings', board: 'Settings', width: 1280, page: 'settings', props: {} },
	{ screen: 'settings', board: 'MobileSettings', width: 390, page: 'settings', props: {} },
];

const DEFAULTS = { boardRoot: 'frame', implRoot: '#view' };

function select(screen, width) {
	return BOARDS
		.filter(b => (!screen || b.screen === screen || b.board === screen) && (!width || b.width === width))
		.map(b => Object.assign({}, DEFAULTS, b));
}

module.exports = { BOARDS, select };
