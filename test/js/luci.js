'use strict';
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..', 'luci', 'htdocs', 'luci-static', 'resources');
const OWN = 'view.monkey-business.';
const REQUIRE = /^\s*'require\s+([\w.-]+)(?:\s+as\s+(\w+))?';/gm;
const baseclass = { extend: (proto) => proto };

if (!String.prototype.format)
	String.prototype.format = function(...args) {
		let i = 0;
		return this.replace(/%[ds]/g, () => String(args[i++]));
	};

function dependency(name, cache) {
	if (name === 'baseclass')
		return baseclass;
	if (name.startsWith(OWN))
		return load(name, cache);
	throw new Error(`model must not depend on LuCI module "${name}"`);
}

function load(name, cache = {}) {
	if (cache[name])
		return cache[name];
	const src = fs.readFileSync(path.join(ROOT, name.replace(/\./g, '/') + '.js'), 'utf8');
	const names = ['_'];
	const values = [(s) => s];
	for (const m of src.matchAll(REQUIRE)) {
		names.push(m[2] || m[1]);
		values.push(dependency(m[1], cache));
	}
	cache[name] = new Function(...names, src)(...values);
	return cache[name];
}

module.exports = { load };
