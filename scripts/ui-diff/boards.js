const BOARDS = [
	{ screen: 'dashboard', board: 'Main', width: 1280, page: 'dashboard', props: {} },
	{ screen: 'dashboard', board: 'MobileDashboard', width: 390, page: 'dashboard', props: {} },
	{ screen: 'servers', board: 'Servers', width: 1280, page: 'servers', props: {} },
	{ screen: 'servers', board: 'MobileServers', state: 'list', width: 390, page: 'servers', props: {}, boardClick: ['button[aria-label="Reorder servers"]'] },
	{ screen: 'servers', board: 'MobileServers', state: 'arrange', width: 390, page: 'servers', props: {}, standClick: ['.mb-srvs-gear', '.mb-tile:nth-child(3)'] },
	{ screen: 'settings', board: 'Settings', width: 1280, page: 'settings', props: {} },
	{ screen: 'settings', board: 'MobileSettings', width: 390, page: 'settings', props: {} },
];

const DEFAULTS = { boardRoot: 'frame', implRoot: '#view', state: '', boardClick: [], standClick: [] };

function select(screen, width) {
	return BOARDS
		.filter(b => (!screen || b.screen === screen || b.board === screen) && (!width || b.width === width))
		.map(b => Object.assign({}, DEFAULTS, b, { label: b.state ? b.board + '-' + b.state : b.board }));
}

module.exports = { BOARDS, select };
