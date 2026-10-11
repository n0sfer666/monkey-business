const fs = require('fs');
const path = require('path');
const pw = require('playwright');
const { ROOT, parse } = require('./args');
const { select } = require('./boards');
const { source, previewHeight, staticTexts } = require('./board');
const { renderBoard, renderStand } = require('./render');
const { match } = require('./match');
const { compare } = require('./compare');
const { pixelDiff } = require('./pixel');
const { loadSecret } = require('./secrets');
const report = require('./report');

const DIFF = { threshold: 0.1, cell: 8, minPx: 16 };

function rect(e) {
	return { x: e.x, y: e.y, w: e.w, h: e.h };
}

async function diff(browser, b, i, matched, file) {
	const page = await browser.newPage();
	try {
		const pairs = matched.pairs.map(p => [rect(b.data.elements[p.b]), rect(i.data.elements[p.i])]);
		const pix = await pixelDiff(page, b.png, i.png, pairs, DIFF);
		fs.writeFileSync(file, pix.png);
		return pix;
	} finally {
		await page.close();
	}
}

async function one(ctx, board, theme) {
	const { browsers, entry, engine, opt, secret, statics, height } = ctx;
	const stem = `${entry.label}-${entry.width}-${theme}-${engine}`;
	const files = { board: board.file, impl: stem + '.impl.png' };
	const impl = await renderStand(browsers[engine], entry, theme, height, secret, path.join(opt.out, files.impl));
	const dark = theme === 'dark';
	const matched = match(board.data, impl.data);
	const cmp = compare(board.data, impl.data, matched, {
		colors: dark, contrast: !dark, isStatic: k => statics.has(String(k).replace(/^icon:/, '')),
	});
	let pix = null;
	if (dark) {
		files.diff = stem + '.diff.png';
		pix = await diff(browsers.diff, board, impl, matched, path.join(opt.out, files.diff));
	}
	const meta = Object.assign({ board: entry.label, page: entry.page, width: entry.width, theme, engine, props: entry.props, date: new Date().toISOString(), load: impl.loaded }, DIFF);
	return report.write(opt.out, stem, { meta, board: board.data, impl: impl.data, matched, cmp, pix, log: impl.log, files });
}

async function main() {
	const opt = parse(process.argv.slice(2));
	const entries = select(opt.screen, opt.width);
	if (!entries.length) throw new Error(`no board for screen=${opt.screen} width=${opt.width}`);
	const secret = loadSecret(ROOT);
	fs.mkdirSync(opt.out, { recursive: true });
	const browsers = {};
	const runs = [];
	try {
		browsers.diff = await pw.chromium.launch();
		for (const e of opt.engines) browsers[e] = e === 'chromium' ? browsers.diff : await pw[e].launch();
		for (const entry of entries) {
			const html = source(opt.boards, entry.board);
			const ctx = { browsers, entry, opt, secret, statics: staticTexts(html), height: Math.max(previewHeight(html), 900) };
			for (const engine of opt.engines) {
				const file = `${entry.label}-${entry.width}-${engine}.board.png`;
				const board = Object.assign({ file }, await renderBoard(browsers[engine], entry, opt.boards, ctx.height, path.join(opt.out, file)));
				for (const theme of opt.themes) {
					const r = await one(Object.assign({ engine }, ctx), board, theme);
					console.log(`${r.stem}: ${r.summary}`);
					runs.push(r);
				}
			}
		}
	} finally {
		report.index(opt.out, runs);
		for (const b of new Set(Object.values(browsers))) await b.close();
	}
	console.log('report: ' + path.relative(process.cwd(), path.join(opt.out, 'index.md')));
}

main().catch(e => { console.error(e.message); process.exit(1); });
