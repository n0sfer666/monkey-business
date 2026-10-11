const fs = require('fs');
const { openBoard } = require('./board');
const { MARK, watch, login, load, mark } = require('./stand');
const { collect } = require('./collect');
const { hostOf, makeScrub, LINK_SOURCE } = require('./secrets');

const MOBILE = 720;
const TEXT_MAX = 120;
const SHOTS = 3;

async function within(browser, width, height, theme, fn) {
	const mobile = width <= MOBILE;
	const ctx = await browser.newContext({
		viewport: { width, height }, colorScheme: theme,
		hasTouch: mobile, isMobile: mobile, deviceScaleFactor: mobile ? 2 : 1,
	});
	try {
		return await fn(await ctx.newPage());
	} finally {
		await ctx.close();
	}
}

function tidy(data, scrub) {
	for (const e of data.elements) {
		for (const f of ['key', 'text', 'value']) if (e[f]) e[f] = scrub(e[f]);
		e.text = e.text.slice(0, TEXT_MAX);
	}
	data.containers = data.containers.map(scrub);
	return data;
}

function shot(page, box, mask) {
	return page.screenshot({ clip: box, fullPage: true, scale: 'css', mask, maskColor: '#7f7f7f' });
}

function renderBoard(browser, entry, dir, height, file) {
	return within(browser, entry.width, height, 'dark', async page => {
		await openBoard(page, dir, entry);
		const data = await page.evaluate(collect, { root: entry.boardRoot });
		if (!data) throw new Error(entry.board + ': nothing collected on the board');
		const png = await shot(page, data.box, []);
		fs.writeFileSync(file, png);
		return { data: tidy(data, String), png };
	});
}

function renderStand(browser, entry, theme, height, secret, file) {
	const scrub = makeScrub(secret), host = hostOf(secret);
	return within(browser, entry.width, height, theme, async page => {
		await login(page);
		const log = watch(page, scrub);
		const loaded = await load(page, entry.page, log);
		if (!loaded.ok) throw new Error(`${entry.page}: stand did not load after ${loaded.attempt} tries: ${scrub(loaded.error)}`);
		const data = await page.evaluate(collect, { root: entry.implRoot });
		if (!data) throw new Error(entry.page + ': nothing collected on the stand');
		for (let i = 0; i < SHOTS; i++) {
			await mark(page, secret, host, LINK_SOURCE);
			const png = await shot(page, data.box, [page.locator(`[${MARK}]`)]);
			if (await mark(page, secret, host, LINK_SOURCE)) continue;
			fs.writeFileSync(file, png);
			return { data: tidy(data, scrub), png, log, loaded };
		}
		throw new Error(entry.page + ': secret text kept re-rendering, screenshot dropped');
	});
}

module.exports = { renderBoard, renderStand };
