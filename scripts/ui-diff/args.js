const path = require('path');

const ROOT = path.resolve(__dirname, '../..');

function parse(argv) {
  const out = {};

  for (let k = 0; k < argv.length; k += 2) out[argv[k].replace(/^--/, '')] = argv[k + 1];
  const list = (v, d) => (v || d).split(',').filter(Boolean);
  const stamp = new Date().toLocaleString('sv-SE').replace(' ', '-').replace(/:/g, '');

  return {
    screen: out.screen || '',
    width: out.width ? Number(out.width) : 0,
    themes: list(out.theme, 'dark,light'),
    engines: list(out.engine, 'chromium,webkit'),
    boards: path.resolve(out.boards || path.join(ROOT, '.context/investigations/ui-diff/boards')),
    out: path.resolve(out.out || path.join(ROOT, '.context/investigations/ui-diff', stamp)),
  };
}

module.exports = { ROOT, parse };
