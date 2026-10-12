const TOL = 2;
const SIZED = new Set(['button', 'input', 'select', 'checkbox', 'icon', 'box', 'tab']);
const PADDED = new Set(['button', 'input', 'select', 'box', 'tab']);
const TEXTUAL = new Set(['text', 'button', 'tab', 'link', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6']);
const SIDES = ['top', 'right', 'bottom', 'left'];

function luminance(hex) {
  const c = [1, 3, 5]
    .map((k) => parseInt(hex.slice(k, k + 2), 16) / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));

  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}

function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);

  return (hi + 0.05) / (lo + 0.05);
}

function styleDiff(b, i, colors) {
  const out = [];
  const add = (prop, expected, actual) => out.push({ prop, expected, actual });
  const same = (prop, x, y) => {
    if (x !== y) add(prop, x, y);
  };
  const near = (prop, x, y) => {
    if (Math.abs(x - y) > TOL) add(prop, x, y);
  };

  same('font-size', b.fs, i.fs);
  same('font-weight', b.fw, i.fw);
  same('font-family', b.ff, i.ff);
  near('height', b.h, i.h);
  if (SIZED.has(b.role)) near('width', b.w, i.w);
  near('radius', b.radius, i.radius);
  near('border-width', b.bw, i.bw);
  if (PADDED.has(b.role)) SIDES.forEach((side, k) => near('padding-' + side, b.pad[k], i.pad[k]));
  if (colors) {
    same('color', b.color, i.color);
    same('background', b.bg, i.bg);
    if (b.bw && i.bw) same('border-color', b.bc, i.bc);
  }

  return out;
}

function lowContrast(e) {
  if (e.disabled || !TEXTUAL.has(e.role) || !e.text) return null;
  const need = e.fs >= 24 || (e.fs >= 18.66 && e.fw >= 700) ? 3 : 4.5;
  const got = contrast(e.fg, e.ebg);

  return got < need ? { need, got: Math.round(got * 100) / 100 } : null;
}

function compare(board, impl, matched, opts) {
  const B = board.elements,
    I = impl.elements;
  const result = { style: [], text: [], data: [], contrast: [] };

  for (const p of matched.pairs) {
    const b = B[p.b],
      i = I[p.i];

    for (const d of styleDiff(b, i, opts.colors)) result.style.push(Object.assign({ b: p.b, i: p.i }, d));
    const s = p.shift;

    if (Math.abs(s.left) > TOL && Math.abs(s.right) > TOL) {
      result.style.push({
        b: p.b,
        i: p.i,
        prop: 'x (от краёв контейнера)',
        expected: `${s.from.left} / ${s.from.right}`,
        actual: `${s.from.left + s.left} / ${s.from.right + s.right}`,
      });
    }
    if (p.via === 'order' && b.key !== i.key) {
      const row = { b: p.b, i: p.i, prop: 'text', expected: b.key || b.text, actual: i.key || i.text };

      (opts.isStatic(b.key) ? result.text : result.data).push(row);
    }
  }
  if (opts.contrast) {
    I.forEach((e, k) => {
      const low = lowContrast(e);

      if (low) result.contrast.push({ i: k, prop: 'contrast', expected: '≥ ' + low.need, actual: low.got });
    });
  }

  return result;
}

module.exports = { compare, contrast };
