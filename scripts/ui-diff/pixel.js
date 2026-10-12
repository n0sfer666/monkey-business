function diffInPage(args) {
  const load = (src) =>
    new Promise((ok, fail) => {
      const im = new Image();

      im.onload = () => ok(im);
      im.onerror = fail;
      im.src = src;
    });
  const pixels = (im, W, H) => {
    const c = document.createElement('canvas');

    c.width = W;
    c.height = H;
    const x = c.getContext('2d');

    x.drawImage(im, 0, 0);

    return x.getImageData(0, 0, W, H).data;
  };
  const blend = (v, a) => 255 + ((v - 255) * a) / 255;
  const maxDelta = 35215 * args.threshold * args.threshold;
  const differs = (p, q, k, j) => {
    const r1 = blend(p[k], p[k + 3]),
      g1 = blend(p[k + 1], p[k + 3]),
      b1 = blend(p[k + 2], p[k + 3]);
    const r2 = blend(q[j], q[j + 3]),
      g2 = blend(q[j + 1], q[j + 3]),
      b2 = blend(q[j + 2], q[j + 3]);
    const dr = r1 - r2,
      dg = g1 - g2,
      db = b1 - b2;
    const y = dr * 0.29889531 + dg * 0.58662247 + db * 0.11448223;
    const i = dr * 0.59597799 - dg * 0.2741761 - db * 0.32180189;
    const q2 = dr * 0.21147017 - dg * 0.52261711 + db * 0.31114694;

    return 0.5053 * y * y + 0.299 * i * i + 0.1957 * q2 * q2 > maxDelta;
  };

  return Promise.all([load(args.board), load(args.impl)]).then(([ib, ii]) => {
    const W = Math.max(ib.width, ii.width),
      H = Math.max(ib.height, ii.height);
    const pb = pixels(ib, W, H),
      pi = pixels(ii, W, H);
    const cell = args.cell,
      cw = Math.ceil(W / cell),
      ch = Math.ceil(H / cell);
    const counts = new Uint32Array(cw * ch);
    const out = document.createElement('canvas');

    out.width = W;
    out.height = H;
    const ctx = out.getContext('2d');

    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, W, H);
    ctx.globalAlpha = 0.3;
    ctx.drawImage(ii, 0, 0);
    ctx.globalAlpha = 1;
    const shade = ctx.getImageData(0, 0, W, H);
    let total = 0;

    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        const k = (y * W + x) * 4;

        if (!differs(pb, pi, k, k)) continue;
        total++;
        counts[Math.floor(y / cell) * cw + Math.floor(x / cell)]++;
        shade.data[k] = 255;
        shade.data[k + 1] = 0;
        shade.data[k + 2] = 0;
        shade.data[k + 3] = 255;
      }
    }
    ctx.putImageData(shade, 0, 0);
    const seen = new Uint8Array(cw * ch),
      regions = [];

    for (let s = 0; s < counts.length; s++) {
      if (!counts[s] || seen[s]) continue;
      const stack = [s];

      seen[s] = 1;
      let px = 0,
        x0 = cw,
        y0 = ch,
        x1 = 0,
        y1 = 0;

      while (stack.length) {
        const c = stack.pop(),
          cx = c % cw,
          cy = Math.floor(c / cw);

        px += counts[c];
        x0 = Math.min(x0, cx);
        y0 = Math.min(y0, cy);
        x1 = Math.max(x1, cx);
        y1 = Math.max(y1, cy);
        for (const [nx, ny] of [
          [cx - 1, cy],
          [cx + 1, cy],
          [cx, cy - 1],
          [cx, cy + 1],
        ]) {
          const n = ny * cw + nx;

          if (nx >= 0 && ny >= 0 && nx < cw && ny < ch && counts[n] && !seen[n]) {
            seen[n] = 1;
            stack.push(n);
          }
        }
      }
      if (px >= args.minPx)
        regions.push({ x: x0 * cell, y: y0 * cell, w: (x1 - x0 + 1) * cell, h: (y1 - y0 + 1) * cell, px });
    }
    regions
      .sort((a, b) => a.y - b.y || a.x - b.x)
      .forEach((r, n) => {
        r.n = n + 1;
        ctx.strokeStyle = '#ffcc00';
        ctx.lineWidth = 2;
        ctx.strokeRect(r.x, r.y, r.w, r.h);
        ctx.fillStyle = '#ffcc00';
        ctx.font = 'bold 12px sans-serif';
        ctx.fillText(String(r.n), r.x + 2, r.y + 12);
      });
    const pairs = args.pairs.map(([b, i]) => {
      const w = Math.max(b.w, i.w),
        h = Math.max(b.h, i.h);
      let px = 0;

      for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
          const bx = b.x + x,
            by = b.y + y,
            ix = i.x + x,
            iy = i.y + y;
          const inB = bx < W && by < H && x < b.w && y < b.h,
            inI = ix < W && iy < H && x < i.w && y < i.h;

          if (inB !== inI) {
            px++;
            continue;
          }
          if (inB && differs(pb, pi, (by * W + bx) * 4, (iy * W + ix) * 4)) px++;
        }
      }

      return { px, ratio: Math.round((px / Math.max(1, w * h)) * 1000) / 10 };
    });

    return { width: W, height: H, total, regions, pairs, png: out.toDataURL('image/png') };
  });
}

async function pixelDiff(page, boardPng, implPng, pairs, opts) {
  const url = (buf) => 'data:image/png;base64,' + buf.toString('base64');
  const r = await page.evaluate(diffInPage, {
    board: url(boardPng),
    impl: url(implPng),
    pairs,
    threshold: opts.threshold,
    cell: opts.cell,
    minPx: opts.minPx,
  });

  return Object.assign(r, { png: Buffer.from(r.png.split(',')[1], 'base64') });
}

module.exports = { pixelDiff };
