const { escape } = require('./regex');

const PLACEHOLDER = /\[[A-Z][A-Z ]*\]/;
const REACH = 64;

function literal(key) {
	return key.replace(new RegExp(PLACEHOLDER.source, 'g'), '').replace(/^icon:/, '').trim() !== '';
}

function keyTest(key) {
	if (!PLACEHOLDER.test(key)) return k => k === key;
	const re = new RegExp('^' + key.split(new RegExp(PLACEHOLDER.source, 'g')).map(escape).join('\\S+') + '$');
	return k => re.test(k);
}

function readingOrder(list) {
	return list.map((e, k) => k).sort((a, b) => Math.round(list[a].y / 4) - Math.round(list[b].y / 4) || list[a].x - list[b].x);
}

function frames(list) {
	const out = new Map([[-1, { x: 0, y: 0, r: Math.max(0, ...list.map(e => e.x + e.w)) }]]);
	for (const e of list) {
		if (e.cid < 0) continue;
		const f = out.get(e.cid) || { x: Infinity, y: Infinity, r: -Infinity };
		out.set(e.cid, { x: Math.min(f.x, e.x), y: Math.min(f.y, e.y), r: Math.max(f.r, e.x + e.w) });
	}
	return out;
}

function place(e, f) {
	return { left: e.x - f.x, right: f.r - e.x - e.w, top: e.y - f.y };
}

function cost(b, i) {
	return Math.min(Math.abs(b.left - i.left), Math.abs(b.right - i.right)) + Math.abs(b.top - i.top);
}

function linkContainers(pairs, B, I) {
	const votes = new Map();
	for (const p of pairs) {
		const key = B[p.b].cid + '|' + I[p.i].cid;
		votes.set(key, (votes.get(key) || 0) + 1);
	}
	const link = new Map([[-1, -1]]);
	const taken = new Set([-1]);
	for (const [key] of [...votes].sort((a, b) => b[1] - a[1])) {
		const [bc, ic] = key.split('|').map(Number);
		if (link.has(bc) || taken.has(ic)) continue;
		link.set(bc, ic);
		taken.add(ic);
	}
	return link;
}

function match(board, impl) {
	const B = board.elements, I = impl.elements;
	const bOrd = readingOrder(B), iOrd = readingOrder(I);
	const usedB = new Set(), usedI = new Set(), pairs = [];
	const take = (b, i, via) => { usedB.add(b); usedI.add(i); pairs.push({ b, i, via }); };
	for (const b of bOrd) {
		if (!B[b].key || !literal(B[b].key)) continue;
		const test = keyTest(B[b].key);
		const i = iOrd.find(k => !usedI.has(k) && I[k].role === B[b].role && test(I[k].key));
		if (i !== undefined) take(b, i, 'text');
	}
	const link = linkContainers(pairs, B, I);
	const bf = frames(B), jf = frames(I);
	const at = (list, f, k) => place(list[k], f.get(list[k].cid));
	const near = [];
	for (const b of bOrd) {
		if (usedB.has(b) || !link.has(B[b].cid)) continue;
		const pb = at(B, bf, b);
		for (const i of iOrd) {
			if (usedI.has(i) || I[i].cid !== link.get(B[b].cid) || I[i].role !== B[b].role) continue;
			const c = cost(pb, at(I, jf, i));
			if (c <= REACH) near.push({ b, i, d: c + ((B[b].role === 'text' ? 0 : Math.abs(B[b].w - I[i].w)) + Math.abs(B[b].h - I[i].h)) / 2 });
		}
	}
	for (const n of near.sort((x, y) => x.d - y.d)) if (!usedB.has(n.b) && !usedI.has(n.i)) take(n.b, n.i, 'order');
	for (const p of pairs) {
		const pb = at(B, bf, p.b), pi = at(I, jf, p.i);
		p.shift = { left: pi.left - pb.left, right: pi.right - pb.right, top: pi.top - pb.top, from: pb };
	}
	return {
		pairs,
		missing: bOrd.filter(k => !usedB.has(k)),
		extra: iOrd.filter(k => !usedI.has(k)),
		containers: [...link].filter(([bc]) => bc >= 0).map(([bc, ic]) => ({ board: board.containers[bc], impl: impl.containers[ic] })),
	};
}

module.exports = { match, keyTest };
