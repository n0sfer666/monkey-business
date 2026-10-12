function collect(opts) {
  const norm = (s) => (s || '').replace(/\s+/g, ' ').trim();
  const near = (a, b) => Math.abs(a - b) < 1;
  const sameRect = (a, b) => {
    const r = a.getBoundingClientRect(),
      s = b.getBoundingClientRect();

    return near(r.x, s.x) && near(r.y, s.y) && near(r.width, s.width) && near(r.height, s.height);
  };
  const frame = () => {
    let e = document.body.firstElementChild;

    while (e && e.children.length === 1 && sameRect(e, e.firstElementChild)) e = e.firstElementChild;

    return e;
  };
  const rgba = (c) => {
    const srgb = /^color\(srgb /.test(c || '');

    if (!/^rgba?\(/.test(c || '') && !srgb) return null;
    const k = srgb ? 255 : 1;
    const [r, g, b, a = 1] = c.match(/[\d.]+/g).map(Number);

    return [r * k, g * k, b * k, a];
  };
  const hex = (v) => {
    if (!v || v[3] === 0) return null;
    const h = v
      .slice(0, 3)
      .map((x) => Math.round(x).toString(16).padStart(2, '0'))
      .join('');

    return (
      '#' +
      h +
      (v[3] < 1
        ? Math.round(v[3] * 255)
            .toString(16)
            .padStart(2, '0')
        : '')
    );
  };
  const over = (top, base) => [0, 1, 2].map((k) => top[k] * top[3] + base[k] * (1 - top[3]));
  const backdrop = (e) => {
    const layers = [];

    for (let x = e; x; x = x.parentElement) {
      const v = rgba(getComputedStyle(x).backgroundColor);

      if (v && v[3] > 0) {
        layers.push(v);
        if (v[3] >= 1) break;
      }
    }

    return layers.reverse().reduce((base, top) => over(top, base), [255, 255, 255]);
  };
  const own = (e) =>
    norm(
      [...e.childNodes]
        .filter((n) => n.nodeType === 3)
        .map((n) => n.textContent)
        .join(' '),
    );
  const CONTROL = 'button, a, [role=button], [role=tab], [role=switch], [role=img]';
  const labelOf = (e) => norm((e.labels && e.labels[0] && e.labels[0].textContent) || '');
  const hasBox = (s) => {
    const b = rgba(s.backgroundColor);

    return (!!b && b[3] > 0) || parseFloat(s.borderTopWidth) > 0 || parseFloat(s.borderBottomWidth) > 0;
  };
  const roleOf = (e, s) => {
    const t = e.tagName.toLowerCase(),
      r = e.getAttribute('role');

    if (t === 'svg') return 'icon';
    if (t === 'input') return e.type === 'checkbox' || e.type === 'radio' ? 'checkbox' : 'input';
    if (t === 'select') return 'select';
    if (t === 'textarea') return 'input';
    if (/^h[1-6]$/.test(t)) return t;
    if (r === 'tab' || (t === 'a' && e.closest('nav'))) return 'tab';
    if (t === 'button' || r === 'button' || r === 'switch') return 'button';
    if (t === 'a') return 'link';
    const host = e.parentElement && e.parentElement.closest(CONTROL);

    if (own(e) && !host) return 'text';
    if (hasBox(s) && !own(e)) return 'box';

    return null;
  };
  const keyOf = (e, role) => {
    const aria = norm(e.getAttribute('aria-label'));

    if (role === 'icon') {
      const c = e.closest(CONTROL);
      const name = c && (norm(c.getAttribute('aria-label')) || norm(c.textContent));

      return name ? 'icon:' + name : '';
    }
    if (role === 'input' || role === 'select' || role === 'checkbox')
      return aria || norm(e.placeholder) || labelOf(e) || norm(e.title);
    if (role === 'box') return '';
    if (role === 'text') return own(e);

    return aria || norm(e.textContent);
  };
  const valueOf = (e, role) => {
    if (role === 'checkbox') return String(e.checked);
    if (role === 'select') return norm(e.selectedOptions && e.selectedOptions[0] && e.selectedOptions[0].text);
    if (role === 'input') return e.value;

    return '';
  };

  const root = opts.root === 'frame' ? frame() : document.querySelector(opts.root);

  if (!root) return null;
  const nodes = [...root.querySelectorAll('*')];
  const containers = [];
  const cidOf = (e) => {
    const c = e.parentElement && e.parentElement.closest('section, [role=dialog], nav, table');

    if (!c || !root.contains(c)) return -1;
    let k = containers.findIndex((x) => x.el === c);

    if (k < 0) {
      const h = c.querySelector('h1, h2, h3, h4');

      containers.push({
        el: c,
        label: norm(c.getAttribute('aria-label')) || (h ? norm(h.textContent) : c.tagName.toLowerCase()),
      });
      k = containers.length - 1;
    }

    return k;
  };
  const elements = [];

  for (const e of nodes) {
    if (e.ownerSVGElement || /^(SCRIPT|STYLE|OPTION|BR|TEMPLATE|NOSCRIPT)$/.test(e.tagName)) continue;
    const r = e.getBoundingClientRect();

    if (!r.width || !r.height || r.right <= 0 || r.left >= innerWidth) continue;
    if (e.checkVisibility && !e.checkVisibility({ opacityProperty: true, visibilityProperty: true })) continue;
    const s = getComputedStyle(e);
    const role = roleOf(e, s);

    if (!role) continue;
    const bg = backdrop(e);
    const fg = rgba(s.color) || [0, 0, 0, 1];

    elements.push({
      role,
      key: keyOf(e, role),
      text: norm(e.innerText || e.textContent),
      value: valueOf(e, role),
      cid: cidOf(e),
      disabled: !!e.disabled || e.getAttribute('aria-disabled') === 'true',
      x: r.x + scrollX,
      y: r.y + scrollY,
      w: r.width,
      h: r.height,
      fs: parseFloat(s.fontSize),
      fw: Number(s.fontWeight) || (s.fontWeight === 'bold' ? 700 : 400),
      ff: /mono|menlo|consolas|courier/i.test(s.fontFamily) ? 'mono' : 'sans',
      color: hex(fg),
      bg: hex(rgba(s.backgroundColor)),
      ebg: hex([...bg, 1]),
      fg: hex([...over(fg, bg), 1]),
      radius: parseFloat(s.borderTopLeftRadius) || 0,
      bw: parseFloat(s.borderTopWidth) || 0,
      bc: parseFloat(s.borderTopWidth) ? hex(rgba(s.borderTopColor)) : null,
      pad: [s.paddingTop, s.paddingRight, s.paddingBottom, s.paddingLeft].map((v) => parseFloat(v) || 0),
    });
  }
  if (!elements.length) return null;
  const x0 = Math.floor(Math.min(...elements.map((e) => e.x))),
    y0 = Math.floor(Math.min(...elements.map((e) => e.y)));
  const x1 = Math.ceil(Math.max(...elements.map((e) => e.x + e.w))),
    y1 = Math.ceil(Math.max(...elements.map((e) => e.y + e.h)));

  for (const e of elements) {
    e.x = Math.round(e.x - x0);
    e.y = Math.round(e.y - y0);
    e.w = Math.round(e.w);
    e.h = Math.round(e.h);
  }

  return {
    box: { x: x0, y: y0, width: x1 - x0, height: y1 - y0 },
    elements,
    containers: containers.map((c) => c.label),
  };
}

module.exports = { collect };
