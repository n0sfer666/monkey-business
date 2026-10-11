const BASE = process.env.MB_UI_BASE || 'http://localhost:8090/cgi-bin/luci';
const PAGES = {
	dashboard: '/admin/services/monkey-business/dashboard',
	servers: '/admin/services/monkey-business/servers',
	settings: '/admin/services/monkey-business/settings',
};
const PASSWORD = process.env.MB_UI_PASSWORD || 'root';
const MARK = 'data-ui-diff-mask';

function watch(page, scrub) {
	const log = { console: [], network: [] };
	page.on('pageerror', e => log.console.push('pageerror: ' + scrub(e.message)));
	page.on('console', m => { if (m.type() === 'error') log.console.push('error: ' + scrub(m.text())); });
	page.on('requestfailed', r => log.network.push('failed ' + (r.failure() || {}).errorText + ' ' + scrub(r.url().replace(BASE, ''))));
	page.on('response', r => { if (r.status() >= 400) log.network.push(r.status() + ' ' + scrub(r.url().replace(BASE, ''))); });
	return log;
}

async function login(page) {
	const field = 'input[name=luci_password]';
	for (let i = 0; i < 4; i++) {
		const res = await page.goto(BASE + PAGES.settings).catch(() => null);
		if (!res) continue;
		if (!(await page.locator(field).count())) return;
		const pass = page.locator(field + ':visible').first();
		try { await pass.waitFor({ timeout: 20000 }); } catch (e) { continue; }
		await pass.fill(PASSWORD);
		await Promise.all([page.waitForLoadState('load'), pass.press('Enter')]);
		if (!(await page.locator(field + ':visible').count())) return;
	}
	throw new Error('stand login failed: ' + BASE);
}

async function load(page, name, log, tries = 3) {
	let last = null;
	for (let i = 0; i < tries; i++) {
		log.console.length = 0;
		log.network.length = 0;
		await page.goto(BASE + PAGES[name]).catch(e => { last = e; });
		try {
			await page.waitForFunction(() => {
				const v = document.querySelector('#view');
				return v && v.children.length && !v.querySelector(':scope > .spinning') && v.innerText.trim().length > 20;
			}, null, { timeout: 25000 });
			await page.waitForTimeout(1200);
			return { ok: true, attempt: i + 1 };
		} catch (e) { last = e; }
	}
	return { ok: false, attempt: tries, error: String(last && last.message).split('\n')[0] };
}

function mark(page, secret, host, linkSource) {
	return page.evaluate(([s, h, src, attr]) => {
		const re = new RegExp(src, 'i');
		const hit = v => { const t = (v || '').toLowerCase(); return !!t && (t.includes(s.toLowerCase()) || (!!h && t.includes(h)) || re.test(v)); };
		let added = 0;
		const tag = el => { if (el && !el.hasAttribute(attr)) { el.setAttribute(attr, ''); added++; } };
		document.querySelectorAll('input, textarea').forEach(el => { if (hit(el.value)) tag(el); });
		document.querySelectorAll('select').forEach(el => { const o = el.selectedOptions[0]; if (o && hit(o.text)) tag(el); });
		const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
		for (let n = walk.nextNode(); n; n = walk.nextNode()) if (hit(n.textContent)) tag(n.parentElement);
		return added;
	}, [secret, host, linkSource, MARK]);
}

module.exports = { BASE, PAGES, MARK, watch, login, load, mark };
