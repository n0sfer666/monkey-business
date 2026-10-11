const fs = require('fs');
const path = require('path');

const HOST = 'http://board.local/';
const SAFE = /^[\w.-]+$/;
const ENTITIES = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&nbsp;': ' ' };

function source(dir, board) {
	return fs.readFileSync(path.join(dir, 'project', board + '.dc.html'), 'utf8');
}

function previewHeight(html) {
	const m = html.match(/"\$preview":\{[^}]*"height":(\d+)/);
	return m ? Number(m[1]) : 900;
}

function decode(s) {
	return s.replace(/&(amp|lt|gt|quot|#39|nbsp);/g, m => ENTITIES[m]).replace(/\s+/g, ' ').trim();
}

function staticTexts(html) {
	const body = html.replace(/<script[\s\S]*?<\/script>/g, '').replace(/<style[\s\S]*?<\/style>/g, '');
	const out = new Set();
	const keep = s => { const t = decode(s); if (t && !t.includes('{{')) out.add(t); };
	for (const m of body.matchAll(/>([^<]+)</g)) keep(m[1]);
	for (const m of body.matchAll(/\s(?:aria-label|placeholder|title|value)="([^"]*)"/g)) keep(m[1]);
	return out;
}

async function openBoard(page, dir, entry) {
	await page.route(HOST + '**', route => {
		const name = new URL(route.request().url()).pathname.slice(1);
		if (!SAFE.test(name)) return route.abort();
		const file = name === 'support.js' ? path.join(dir, 'artifact-type/dc-runtime.js') : path.join(dir, 'project', name);
		return route.fulfill({ path: file });
	});
	await page.goto(HOST + entry.board + '.dc.html');
	await page.waitForFunction(() => window.__dcRootName && document.body.innerText.trim().length > 0, null, { timeout: 15000 });
	if (Object.keys(entry.props).length) await page.evaluate(p => window.__dcSetProps(window.__dcRootName(), p), entry.props);
	await page.waitForTimeout(400);
}

module.exports = { source, previewHeight, staticTexts, openBoard };
